import { Controller } from "@hotwired/stimulus"

// El horario de una sección en una grilla semanal: de lunes a sábado, de 6:00 am a 10:00 pm, todo en hora normal.
//
// Nació en FAU el 17-nov y llegó a FHE el 23-nov (los horarios nacen en FAU, el más adelantado en eso). Reemplaza al
// formulario anidado de rails_admin (horario → bloques, con un campo de hora de 24 h) y al modal copiado de la
// Programación. La hora se marca donde se ve, con la mañana, la tarde y la noche a la vista:
//
//   arrastrar        de la hora de inicio a la final; si abarca varios días, la misma clase en cada uno
//   clic y clic      lo mismo, sin arrastrar: un clic en el inicio y otro en el final (Esc cancela)
//   mover, estirar   un bloque se arrastra a otra hora u otro día, y se estira por arriba o por abajo
//   la lista         el ajuste fino de 5 en 5 minutos, el día, la modalidad y el aula de cada bloque
//
// Lo que cambia con el de FAU, porque FHE guarda más en cada bloque:
//   · la grilla salta de 15 en 15 minutos: FHE usa horas académicas de 45 (1 h 30, 2 h 15…), y 1 de cada 3 bloques
//     cae en un cuarto de hora (1.326 de 4.060 desde 2025);
//   · cada bloque lleva su modalidad y su aula, y uno nuevo hereda las del bloque anterior (Daniel, 20-nov: «un
//     bloque ↔ un aula, que frecuentemente es la misma pero se permiten excepciones»);
//   · una clase dura media hora por lo menos (Timeblock::DURACION_MINIMA);
//   · los bloques cuelgan del horario de la sección (Timetable). Si no queda ninguno, el horario se borra; si nada
//     cambió, no viaja nada (así se siguen guardando las secciones con horarios viejos);
//   · un bloque guardado que cambia de día u hora viaja como borrar + nuevo. Rails borra primero, después actualiza
//     y al final crea, así que el índice único de la base (día + inicio, día + fin) nunca ve dos bloques iguales.
//
// El servidor valida igual que siempre y tiene la última palabra.
const DIAS = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado"]
const MODALIDADES = ["Presencial", "Virtual"]
const DESDE = 6 * 60         // 6:00 am, como Timeblock::HORA_MINIMA
const HASTA = 22 * 60        // 10:00 pm, como Timeblock::HORA_MAXIMA
const MINIMO = 30            // la clase más corta, como Timeblock::DURACION_MINIMA
const PASO = 15              // la grilla, en minutos
const FINO = 5               // la lista
const HORA_ACADEMICA = 45    // lo que dura un bloque marcado con dos clics en el mismo cuarto de hora
const MEDIODIA = 12 * 60

const dos = (n) => String(n).padStart(2, "0")
const hora = (m) => { const h = Math.floor(m / 60); return `${(h + 11) % 12 + 1}:${dos(m % 60)} ${h < 12 ? "am" : "pm"}` }
const hhmm = (m) => `${dos(Math.floor(m / 60))}:${dos(m % 60)}`
const aMinutos = (texto) => { const [h, m] = String(texto || "").split(":").map(Number); return Number.isFinite(h) ? h * 60 + (m || 0) : null }
const duracion = (m) => [Math.floor(m / 60) && `${Math.floor(m / 60)} h`, m % 60 && `${m % 60} min`].filter(Boolean).join(" ")
const entre = (v, a, b) => Math.min(b, Math.max(a, v))
const fuera = (m) => m < DESDE || m > HASTA
const valido = (b) => !fuera(b.inicio) && !fuera(b.fin) && b.fin - b.inicio >= MINIMO
const abajo = (m) => Math.floor(m / PASO) * PASO
const nombreDia = (d) => DIAS[d].toLowerCase()
const porDiaYHora = (x, y) => x.dia - y.dia || x.inicio - y.inicio
const escapar = (texto) => String(texto ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c])
// El globo de Bootstrap de lo que dibuja la grilla (controlador «globo»), con media espera: sin ella, al cruzar un
// bloque con el ratón saltaban uno tras otro los globos de sus bordes.
const globo = (texto, lugar = "top") =>
  `title="${texto}" data-controller="globo" data-bs-placement="${lugar}" data-bs-delay='{"show":500,"hide":0}'`

export default class extends Controller {
  static targets = ["dias", "columna", "lista", "campos", "guia", "anuncio", "servidor"]
  static values = { bloques: Array, prefijo: String, horario: String }

  connect() {
    this.siguiente = 0
    this.bloques = this.bloquesValue.map((h) => ({
      clave: h.id ? String(h.id) : this.nuevaClave(),
      id: h.id || null,
      dia: Math.max(0, DIAS.indexOf(h.dia)),
      inicio: aMinutos(h.inicio) ?? 7 * 60,
      fin: aMinutos(h.fin) ?? 9 * 60,
      modalidad: MODALIDADES.includes(h.modalidad) ? h.modalidad : MODALIDADES[0],
      aula: h.aula || "",
      borrar: !!h.borrar,
      original: h.original && {
        dia: DIAS.indexOf(h.original.dia), inicio: aMinutos(h.original.inicio), fin: aMinutos(h.original.fin),
        modalidad: h.original.modalidad, aula: h.original.aula || "",
      },
    }))
    this.guiaInicial = this.guiaTarget.textContent.trim()
    this.dibujar()
  }

  // ── La grilla ────────────────────────────────────────────────────────────────────────────────────

  presionar(event) {
    if (event.button !== 0 || event.target.closest(".hs-x")) return
    event.preventDefault()
    const marca = !this.ancla && event.target.closest(".hs-bloque--error")
    if (marca) {
      this.seleccionado = marca.dataset.clave
      return this.dibujar({ enfocar: [marca.dataset.clave, "fin"] })
    }
    this.diasTarget.setPointerCapture(event.pointerId)
    const punto = this.punto(event)
    const bloque = !this.ancla && event.target.closest(".hs-bloque")
    const comun = { desde: punto, x: event.clientX, y: event.clientY, movio: false }
    if (bloque) {
      const b = this.bloque(bloque.dataset.clave)
      const borde = event.target.closest(".hs-tirador")?.dataset.borde
      this.gesto = { ...comun, tipo: borde || "mover", b, antes: { ...b } }
    } else {
      this.gesto = { ...comun, tipo: "crear" }
    }
  }

  arrastrar(event) {
    const punto = this.punto(event)
    const g = this.gesto
    if (!g) {
      if (this.ancla) this.fantasma(this.ancla, punto)
      return
    }
    if (!g.movio && Math.hypot(event.clientX - g.x, event.clientY - g.y) < 4) return
    g.movio = true
    if (g.tipo === "crear") return this.fantasma(g.desde, punto)

    const { b, antes } = g
    if (g.tipo === "mover") {
      // Se mueve de cuarto en cuarto de hora sin perder sus minutos: una de 8:50 a 10:20 sigue en :50.
      const largo = antes.fin - antes.inicio
      const delta = Math.round((punto.minuto - g.desde.minuto) / PASO) * PASO
      b.inicio = entre(antes.inicio + delta, DESDE, HASTA - largo)
      b.fin = b.inicio + largo
      b.dia = punto.dia
    } else if (g.tipo === "inicio") {
      b.inicio = entre(Math.round(punto.minuto / PASO) * PASO, DESDE, antes.fin - MINIMO)
    } else {
      b.fin = entre(Math.round(punto.minuto / PASO) * PASO, antes.inicio + MINIMO, HASTA)
    }
    this.dibujarGrilla()
  }

  soltar(event) {
    const g = this.gesto
    this.gesto = null
    if (this.diasTarget.hasPointerCapture(event.pointerId)) this.diasTarget.releasePointerCapture(event.pointerId)
    if (!g) return

    if (g.tipo === "crear") {
      if (g.movio) return this.crear(g.desde, this.punto(event))
      if (this.ancla) return this.crear(this.ancla, g.desde)
      this.ancla = g.desde
      this.fantasma(g.desde, g.desde)
      return this.guiar(`Empieza el ${nombreDia(g.desde.dia)} a las ${hora(abajo(g.desde.minuto))}. Ahora haga clic donde termina la clase; puede ser en otro día para repetirla. Esc cancela.`)
    }
    if (!g.movio) {
      this.seleccionado = g.b.clave
      this.dibujar()
      return this.enfocarBloque(g.b.clave)
    }
    this.seleccionado = g.b.clave
    this.cambio(`Quedó el ${nombreDia(g.b.dia)} de ${hora(g.b.inicio)} a ${hora(g.b.fin)}.`)
  }

  // El puntero salió de la grilla sin estar arrastrando: con el primer clic dado, queda solo ese.
  salir() {
    if (!this.gesto && this.ancla) this.fantasma(this.ancla, this.ancla)
  }

  cancelar() {
    if (this.gesto?.antes) Object.assign(this.gesto.b, this.gesto.antes)
    this.gesto = null
    this.ancla = null
    this.guiar()
    this.dibujar()
  }

  tecla(event) {
    if (event.key === "Escape" && (this.gesto || this.ancla)) {
      event.preventDefault()
      return this.cancelar()
    }
    const bloque = event.target.closest?.(".hs-bloque")
    if (bloque && this.element.contains(bloque) && ["Delete", "Backspace"].includes(event.key)) {
      event.preventDefault()
      this.quitarClave(bloque.dataset.clave)
    }
  }

  // ── Los cambios ──────────────────────────────────────────────────────────────────────────────────

  crear(a, b) {
    const { primero, ultimo, inicio, fin } = this.rango(a, b)
    for (let dia = primero; dia <= ultimo; dia++) {
      this.bloques.push({ clave: this.nuevaClave(), id: null, dia, inicio, fin, borrar: false, ...this.heredado(dia, inicio) })
    }
    this.ancla = null
    this.seleccionado = null
    this.guiar()
    const dias = primero === ultimo ? `el ${nombreDia(primero)}` : `de ${nombreDia(primero)} a ${nombreDia(ultimo)}`
    this.cambio(`Se agregó ${dias}, de ${hora(inicio)} a ${hora(fin)}.`)
  }

  // Lo que abarca un arrastre (o dos clics), de cuarto en cuarto de hora. Si queda más corto que una clase, una
  // hora académica: con dos clics en el mismo cuarto de hora quedaban 15 minutos, que el servidor no acepta.
  rango(a, b) {
    let inicio = abajo(Math.min(a.minuto, b.minuto))
    let fin = Math.min(HASTA, abajo(Math.max(a.minuto, b.minuto)) + PASO)
    if (fin - inicio < MINIMO) {
      fin = Math.min(HASTA, inicio + HORA_ACADEMICA)
      inicio = Math.min(inicio, fin - HORA_ACADEMICA)
    }
    return { primero: Math.min(a.dia, b.dia), ultimo: Math.max(a.dia, b.dia), inicio, fin }
  }

  // Un bloque nuevo hereda la modalidad y el aula del bloque anterior en la semana; si es el primero, del que le
  // sigue. Sin ninguno, presencial y sin aula.
  heredado(dia, inicio) {
    const otros = this.activos().sort(porDiaYHora)
    const fuente = otros.filter((b) => b.dia < dia || (b.dia === dia && b.inicio < inicio)).pop() || otros[0]
    return { modalidad: fuente?.modalidad || MODALIDADES[0], aula: fuente?.aula || "" }
  }

  // «+ Agregar horario», para hacerlo sin la grilla: el día siguiente que esté libre, a la misma hora que el último.
  agregar() {
    const activos = this.activos()
    const ultimo = activos.filter(valido).sort(porDiaYHora).pop()
    const ocupados = new Set(activos.map((b) => b.dia))
    const libres = DIAS.map((_, d) => d).filter((d) => !ocupados.has(d))
    const dia = libres.find((d) => !ultimo || d > ultimo.dia) ?? libres[0] ?? 0
    const [inicio, fin] = ultimo ? [ultimo.inicio, ultimo.fin] : [7 * 60, 7 * 60 + 2 * HORA_ACADEMICA]
    const b = { clave: this.nuevaClave(), id: null, dia, inicio, fin, borrar: false, ...this.heredado(dia, inicio) }
    this.bloques.push(b)
    this.seleccionado = b.clave
    this.cambio(`Se agregó el ${nombreDia(dia)}, de ${hora(inicio)} a ${hora(fin)}.`, { enfocar: [b.clave, "dia"] })
  }

  cambiarDia(event) {
    const b = this.deLaFila(event)
    b.dia = Number(event.target.value)
    this.seleccionado = b.clave
    this.cambio(`Quedó el ${nombreDia(b.dia)} de ${hora(b.inicio)} a ${hora(b.fin)}.`, { enfocar: [b.clave, "dia"] })
  }

  cambiarHora(event) {
    const b = this.deLaFila(event)
    const campo = event.target.dataset.campo
    const valor = Number(event.target.value)
    if (campo === "inicio") {
      // El final se queda donde estaba, salvo que la clase quede muy corta: entonces se corre con la misma duración.
      const largo = b.fin - b.inicio >= MINIMO ? b.fin - b.inicio : 2 * HORA_ACADEMICA
      b.inicio = valor
      if (b.fin - b.inicio < MINIMO) b.fin = Math.min(HASTA, b.inicio + largo)
    } else {
      b.fin = valor
    }
    this.seleccionado = b.clave
    this.cambio(`Quedó el ${nombreDia(b.dia)} de ${hora(b.inicio)} a ${hora(b.fin)}.`, { enfocar: [b.clave, campo] })
  }

  cambiarModalidad(event) {
    const b = this.deLaFila(event)
    b.modalidad = event.target.value
    this.seleccionado = b.clave
    this.cambio(`El ${nombreDia(b.dia)} de ${hora(b.inicio)} quedó ${b.modalidad.toLowerCase()}.`, { enfocar: [b.clave, "modalidad"] })
  }

  // El aula se escribe en mayúsculas, como en el admin. La lista no se redibuja mientras se escribe (perdería el
  // cursor): solo los campos que viajan y el rótulo del bloque en la grilla.
  escribirAula(event) {
    const campo = event.target
    const b = this.deLaFila(event)
    const cursor = campo.selectionStart
    campo.value = campo.value.toUpperCase()
    campo.setSelectionRange(cursor, cursor)
    b.aula = campo.value
    this.seleccionado = b.clave
    if (this.hasServidorTarget) this.servidorTarget.remove()
    this.dibujarGrilla()
    this.escribirCampos()
  }

  // Un horario viejo que no pasa la regla (de antes de la grilla) ofrece la corrección con un clic.
  corregir(event) {
    const b = this.deLaFila(event)
    b.inicio = Number(event.currentTarget.dataset.inicio)
    b.fin = Number(event.currentTarget.dataset.fin)
    this.seleccionado = b.clave
    this.cambio(`Quedó el ${nombreDia(b.dia)} de ${hora(b.inicio)} a ${hora(b.fin)}.`)
  }

  quitar(event) {
    this.quitarClave(event.currentTarget.closest("[data-clave]").dataset.clave)
  }

  quitarClave(clave) {
    const b = this.bloque(clave)
    if (!b) return
    this.sacar(b)
    this.cambio(`Se quitó el ${nombreDia(b.dia)} de ${hora(b.inicio)} a ${hora(b.fin)}.`)
  }

  cambio(mensaje, { enfocar } = {}) {
    this.normalizar()
    if (this.hasServidorTarget) this.servidorTarget.remove()
    this.dibujar({ enfocar })
    this.anuncioTarget.textContent = mensaje
  }

  // Dos bloques del mismo día que se pisan o se tocan quedan en uno solo: el que ya estaba guardado, si alguno lo
  // estaba, con su modalidad y su aula. En FHE no hay dos bloques así (0 pares desde 2025).
  normalizar() {
    DIAS.forEach((_, dia) => {
      const delDia = this.activos().filter((b) => b.dia === dia && valido(b)).sort((x, y) => x.inicio - y.inicio)
      let actual = null
      delDia.forEach((b) => {
        if (actual && b.inicio <= actual.fin) {
          const [queda, sale] = !actual.id && b.id ? [b, actual] : [actual, b]
          queda.inicio = Math.min(actual.inicio, b.inicio)
          queda.fin = Math.max(actual.fin, b.fin)
          this.sacar(sale)
          if (this.seleccionado === sale.clave) this.seleccionado = queda.clave
          actual = queda
        } else {
          actual = b
        }
      })
    })
  }

  // ── Dibujar ──────────────────────────────────────────────────────────────────────────────────────

  dibujar({ enfocar } = {}) {
    this.dibujarGrilla()
    this.dibujarLista()
    this.escribirCampos()
    if (!enfocar) return
    const [clave, campo] = enfocar
    const fila = this.listaTarget.querySelector(`[data-clave="${clave}"]`)
    fila?.querySelector(campo === "dia" ? ".hs-campo-dia" : `[data-campo="${campo}"]`)?.focus()
  }

  dibujarGrilla() {
    const porDia = DIAS.map(() => [])
    this.activos().forEach((b) => porDia[b.dia].push(b))
    this.columnaTargets.forEach((columna, dia) => {
      columna.innerHTML = porDia[dia].map((b) => (valido(b) ? this.htmlBloque(b) : this.htmlMarca(b))).join("")
    })
  }

  // La vista previa mientras se arrastra (o después del primer clic): el rectángulo en cada día que abarca.
  fantasma(a, b) {
    this.dibujarGrilla()
    const { primero, ultimo, inicio, fin } = this.rango(a, b)
    for (let dia = primero; dia <= ultimo; dia++) {
      const rotulo = dia === primero ? `<span class="hs-rango">${hora(inicio)} – ${hora(fin)}</span>` : ""
      this.columnaTargets[dia].insertAdjacentHTML("beforeend", `<div class="hs-bloque hs-bloque--fantasma" style="${this.posicion(inicio, fin)}">${rotulo}</div>`)
    }
  }

  // El lugar del bloque, debajo de la hora: el aula, y «Virtual» si es virtual.
  lugar(b) {
    return [b.modalidad === "Virtual" && "Virtual", b.aula.trim()].filter(Boolean).join(" · ")
  }

  htmlBloque(b) {
    const clases = ["hs-bloque", b.modalidad === "Virtual" && "hs-bloque--virtual",
      b.clave === this.seleccionado && "is-seleccionado", b.fin - b.inicio <= MINIMO && "hs-bloque--corto"]
    const lugar = this.lugar(b)
    return `<div class="${clases.filter(Boolean).join(" ")}" data-clave="${b.clave}" tabindex="0" role="button"
        aria-label="${DIAS[b.dia]} de ${hora(b.inicio)} a ${hora(b.fin)}${lugar ? `, ${escapar(lugar)}` : ""}. Suprimir lo quita." style="${this.posicion(b.inicio, b.fin)}">
      <span class="hs-tirador" data-borde="inicio" ${globo("Arrastre para cambiar la hora de inicio")}></span>
      <span class="hs-rango">${hora(b.inicio)} – ${hora(b.fin)}</span>
      ${lugar ? `<span class="hs-lugar">${escapar(lugar)}</span>` : ""}
      <button type="button" class="hs-x" ${globo("Quitar")} aria-label="Quitar" data-action="horario-semanal#quitar">×</button>
      <span class="hs-tirador" data-borde="fin" ${globo("Arrastre para cambiar la hora final", "bottom")}></span>
    </div>`
  }

  // Un horario viejo que no pasa la regla no se puede dibujar: queda una marca roja en su hora de inicio (arriba, si
  // esa hora también está fuera) que lleva a su fila de la lista, donde está la corrección.
  htmlMarca(b) {
    const inicio = entre(b.inicio, DESDE, HASTA - 60)
    return `<div class="hs-bloque hs-bloque--error${b.clave === this.seleccionado ? " is-seleccionado" : ""}" data-clave="${b.clave}"
        tabindex="0" role="button" ${globo("Este horario no es válido: corríjalo en la lista")}
        aria-label="${DIAS[b.dia]} de ${hora(b.inicio)} a ${hora(b.fin)}: no es válido, corríjalo en la lista" style="${this.posicion(inicio, inicio + 60)}">
      <span class="hs-rango">⚠ ${hora(b.inicio)} – ${hora(b.fin)}</span>
    </div>`
  }

  posicion(inicio, fin) {
    const total = HASTA - DESDE
    return `top: ${((inicio - DESDE) / total) * 100}%; height: ${((fin - inicio) / total) * 100}%`
  }

  dibujarLista() {
    const filas = this.activos().sort(porDiaYHora)
    this.listaTarget.innerHTML = filas.length
      ? filas.map((b) => this.htmlFila(b)).join("")
      : `<li class="hs-vacia">Sin horario todavía.</li>`
  }

  // Día | inicio a fin | duración | 🗑, y debajo (o al lado, si hay sitio) modalidad | aula.
  htmlFila(b) {
    const error = this.error(b)
    const clases = ["hs-fila", b.clave === this.seleccionado && "is-seleccionado", error && "hs-fila--error"]
    const dias = DIAS.map((d, i) => `<option value="${i}"${i === b.dia ? " selected" : ""}>${d}</option>`).join("")
    const modalidades = MODALIDADES.map((m) => `<option value="${m}"${m === b.modalidad ? " selected" : ""}>${m}</option>`).join("")
    const correcciones = error ? error.sugerencias.map((s) =>
      `<button type="button" class="btn btn-sm btn-outline-danger hs-corregir" data-inicio="${s.inicio}" data-fin="${s.fin}"
        data-action="horario-semanal#corregir">¿${hora(s.inicio)} – ${hora(s.fin)}?</button>`).join("") : ""
    return `<li class="${clases.filter(Boolean).join(" ")}" data-clave="${b.clave}">
      <select class="form-select form-select-sm hs-campo-dia" aria-label="Día" data-action="horario-semanal#cambiarDia">${dias}</select>
      <select class="form-select form-select-sm hs-campo-hora" aria-label="Hora de inicio" data-campo="inicio"
        data-action="horario-semanal#cambiarHora">${this.opciones(b.inicio, DESDE, HASTA - MINIMO)}</select>
      <span class="hs-a">a</span>
      <select class="form-select form-select-sm hs-campo-hora" aria-label="Hora final" data-campo="fin"
        data-action="horario-semanal#cambiarHora">${this.opciones(b.fin, valido(b) ? b.inicio + MINIMO : DESDE, HASTA)}</select>
      <span class="hs-duracion">${valido(b) ? duracion(b.fin - b.inicio) : ""}</span>
      <button type="button" class="btn btn-sm hs-quitar" ${globo("Quitar")} aria-label="Quitar este bloque"
        data-action="horario-semanal#quitar"><i class="fas fa-trash"></i></button>
      <select class="form-select form-select-sm hs-campo-modalidad" aria-label="Modalidad" data-campo="modalidad"
        data-action="horario-semanal#cambiarModalidad">${modalidades}</select>
      <input type="text" class="form-control form-control-sm hs-campo-aula" aria-label="Aula" placeholder="Aula" maxlength="40"
        autocomplete="off" value="${escapar(b.aula)}" data-campo="aula" data-action="input->horario-semanal#escribirAula">
      ${error ? `<div class="hs-error">${error.texto} ${correcciones}</div>` : ""}
    </li>`
  }

  // Las horas de 5 en 5 minutos, separadas en mañana, tarde y noche. Una hora vieja que no está en la lista
  // (fuera del horario de clases, o con minutos sueltos) se muestra arriba, para no cambiarla sin que se vea.
  opciones(valor, desde, hasta) {
    const grupos = [["Mañana", 0, MEDIODIA], ["Tarde", MEDIODIA, 18 * 60], ["Noche", 18 * 60, 24 * 60]]
    const enLista = valor >= desde && valor <= hasta && valor % FINO === 0
    const suelta = enLista ? "" : `<option value="${valor}" selected>${hora(valor)}${fuera(valor) ? " (fuera del horario)" : ""}</option>`
    return suelta + grupos.map(([nombre, g1, g2]) => {
      let html = ""
      for (let m = Math.ceil(Math.max(desde, g1) / FINO) * FINO; m <= Math.min(hasta, g2 - 1); m += FINO) {
        html += `<option value="${m}"${m === valor ? " selected" : ""}>${hora(m)}</option>`
      }
      return html && `<optgroup label="${nombre}">${html}</optgroup>`
    }).join("")
  }

  // La misma regla de Timeblock#dentro_del_horario_de_clases, con la corrección probable: la hora de la tarde
  // (11:00 am – 1:00 am ──► 1:00 pm), el inicio de la mañana si empieza de noche y termina de mañana, o una hora
  // académica si quedó muy corta.
  error(b) {
    if (valido(b)) return null
    let texto
    if (fuera(b.inicio)) texto = `${hora(b.inicio)} está fuera del horario de clases (6:00 am a 10:00 pm).`
    else if (fuera(b.fin)) texto = `${hora(b.fin)} está fuera del horario de clases (6:00 am a 10:00 pm).`
    else if (b.fin <= b.inicio) texto = `Termina (${hora(b.fin)}) antes de empezar (${hora(b.inicio)}).`
    else texto = `Dura ${duracion(b.fin - b.inicio)}: una clase dura por lo menos media hora.`
    const tarde = (m) => (m < MEDIODIA ? m + MEDIODIA : m)
    const manana = (m) => (m >= MEDIODIA ? m - MEDIODIA : m)
    const candidatas = [
      { inicio: fuera(b.inicio) ? tarde(b.inicio) : b.inicio, fin: tarde(b.fin) },
      { inicio: manana(b.inicio), fin: fuera(b.fin) ? tarde(b.fin) : b.fin },
      { inicio: b.inicio, fin: Math.min(HASTA, b.inicio + HORA_ACADEMICA) },
    ]
    const vistas = new Set()
    const sugerencias = candidatas.filter((c) => {
      const clave = `${c.inicio}-${c.fin}`
      if (!valido(c) || vistas.has(clave) || (c.inicio === b.inicio && c.fin === b.fin)) return false
      vistas.add(clave)
      return true
    })
    return { texto, sugerencias }
  }

  // Los campos que viajan con el formulario, los mismos del formulario anidado de rails_admin:
  //   «prefijo»[id]                                          el horario, si ya existe
  //   «prefijo»[_destroy]                                    1, si no le quedó ningún bloque
  //   «prefijo»[timeblocks_attributes][N][id, day, …]        cada bloque
  // Si nada cambió, no viaja nada y el horario queda como estaba.
  escribirCampos() {
    const prefijo = this.prefijoValue
    const campo = (nombre, valor) => `<input type="hidden" name="${prefijo}${nombre}" value="${escapar(valor)}">`
    if (!this.huboCambios()) return (this.camposTarget.innerHTML = "")

    const horario = this.horarioValue ? campo("[id]", this.horarioValue) : ""
    if (!this.activos().length) {
      this.camposTarget.innerHTML = horario && horario + campo("[_destroy]", "1")
      return
    }
    const bloque = (clave, valores) => Object.entries(valores)
      .map(([nombre, valor]) => campo(`[timeblocks_attributes][${clave}][${nombre}]`, valor)).join("")
    const datos = (b) => ({ day: DIAS[b.dia], start_time: hhmm(b.inicio), end_time: hhmm(b.fin), modality: b.modalidad,
      classroom: b.aula.trim(), _destroy: "false" })
    this.camposTarget.innerHTML = horario + this.bloques.map((b) => {
      if (!b.id) return bloque(b.clave, datos(b))
      if (b.borrar) return bloque(b.clave, { id: b.id, _destroy: "1" })
      if (!this.movido(b)) return bloque(b.clave, { id: b.id, modality: b.modalidad, classroom: b.aula.trim(), _destroy: "false" })
      b.claveNueva ||= this.nuevaClave()
      return bloque(b.clave, { id: b.id, _destroy: "1" }) + bloque(b.claveNueva, datos(b))
    }).join("")
  }

  huboCambios() {
    return this.bloques.some((b) => !b.id || b.borrar || this.movido(b) || b.modalidad !== b.original.modalidad ||
      b.aula.trim() !== b.original.aula.trim())
  }

  // Un bloque guardado que ya no está en el día y las horas que tiene en la base.
  movido(b) {
    const o = b.original
    return !o || b.dia !== o.dia || b.inicio !== o.inicio || b.fin !== o.fin
  }

  // ── Utilidades ───────────────────────────────────────────────────────────────────────────────────

  punto(event) {
    const r = this.diasTarget.getBoundingClientRect()
    return {
      dia: entre(Math.floor((event.clientX - r.left) / (r.width / DIAS.length)), 0, DIAS.length - 1),
      minuto: entre(DESDE + ((event.clientY - r.top) / r.height) * (HASTA - DESDE), DESDE, HASTA - 1),
    }
  }

  guiar(texto) {
    this.guiaTarget.textContent = texto || this.guiaInicial
    this.guiaTarget.classList.toggle("hs-guia--activa", Boolean(texto))
  }

  enfocarBloque(clave) {
    this.columnaTargets.flatMap((c) => [...c.children]).find((e) => e.dataset.clave === clave)?.focus({ preventScroll: true })
  }

  activos() {
    return this.bloques.filter((b) => !b.borrar)
  }

  bloque(clave) {
    return this.bloques.find((b) => b.clave === clave)
  }

  deLaFila(event) {
    return this.bloque(event.target.closest("[data-clave]").dataset.clave)
  }

  sacar(b) {
    if (b.id) b.borrar = true
    else this.bloques.splice(this.bloques.indexOf(b), 1)
  }

  // Numérica, como las de los formularios anidados de rails_admin: strong params solo deja pasar en
  // timeblocks_attributes las claves de números (en FAU, con «nuevo…», el panel de la Programación perdía los horarios).
  nuevaClave() {
    return `${Date.now()}${String(this.siguiente++).padStart(3, "0")}`
  }
}
