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
// En el panel de la Programación (23-nov), la grilla muestra además lo que rodea al horario, en tres capas que se
// prenden y se apagan arriba de la grilla (los datos son de CapasDelHorario):
//
//   el profesor        sus otras clases del período, rayadas. Si un bloque pisa una, el bloque lleva un aro ámbar
//                      y el aviso dice con cuál, con tres salidas (Daniel): mover el bloque, «Se dictan juntas» o
//                      «Guardar igual». Si el choque es nuevo, Crear o Guardar esperan a que se elija una; si ya
//                      estaba al abrir la sección, solo se avisa
//   las otras secciones de la asignatura, con borde punteado
//   el semestre        las otras asignaturas del semestre y las que se cursaron junto con esta, en un tono suave. Si
//                      con una de estas no queda combinación posible, el aviso lo dice
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
const sePisan = (a, b) => a.dia === b.dia && a.inicio < b.fin && b.inicio < a.fin
const enLista = (textos) => (textos.length < 2 ? textos.join("") : `${textos.slice(0, -1).join(", ")} y ${textos[textos.length - 1]}`)
// Los bloques de las capas, como los de la sección: el día por su número y las horas en minutos.
const enMinutos = (bloques = []) => bloques
  .map((b) => ({ dia: DIAS.indexOf(b.dia), inicio: aMinutos(b.inicio), fin: aMinutos(b.fin), aula: b.aula || "" }))
  .filter((b) => b.dia >= 0 && valido(b))
// Las capas que cada quien apaga se recuerdan en su navegador. Es solo una comodidad: sin eso, se ven todas.
const OCULTAS = "coes.horario-semanal.capas-ocultas"
const capasOcultas = () => {
  try { const guardadas = JSON.parse(localStorage.getItem(OCULTAS)); return Array.isArray(guardadas) ? guardadas : [] } catch { return [] }
}
const guardarCapasOcultas = (capas) => {
  try { localStorage.setItem(OCULTAS, JSON.stringify([...capas])) } catch { /* el navegador no deja guardar: no pasa nada */ }
}

export default class extends Controller {
  static targets = ["dias", "columna", "lista", "campos", "guia", "anuncio", "servidor", "ver", "avisos", "camposSeccion"]
  static values = { bloques: Array, prefijo: String, horario: String, capas: Object, ocupacion: String }

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
    if (this.hasCapasValue) this.prepararCapas()
    this.dibujar()
  }

  disconnect() {
    this.formulario?.removeEventListener("submit", this.alEnviar)
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
    if (this.conPista) this.guiar()
    this.normalizar()
    if (this.hasServidorTarget) this.servidorTarget.remove()
    this.dibujar({ enfocar })
    this.anuncioTarget.textContent = [mensaje, this.textoDelChoque()].filter(Boolean).join(" ")
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
    const choques = this.capas && this.choquesActuales()
    this.queChocan = new Set(choques ? [...choques.values()].flatMap((c) => c.mios) : [])
    const porDia = DIAS.map(() => [])
    this.activos().forEach((b) => porDia[b.dia].push(b))
    this.columnaTargets.forEach((columna, dia) => {
      columna.innerHTML = porDia[dia].map((b) => (valido(b) ? this.htmlBloque(b) : this.htmlMarca(b))).join("")
    })
    if (choques) this.actualizarAlrededor(choques)
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
    const choca = this.queChocan?.has(b.clave)
    const clases = ["hs-bloque", b.modalidad === "Virtual" && "hs-bloque--virtual", choca && "hs-bloque--choca",
      b.clave === this.seleccionado && "is-seleccionado", b.fin - b.inicio <= MINIMO && "hs-bloque--corto"]
    const lugar = this.lugar(b)
    return `<div class="${clases.filter(Boolean).join(" ")}" data-clave="${b.clave}" tabindex="0" role="button"
        aria-label="${DIAS[b.dia]} de ${hora(b.inicio)} a ${hora(b.fin)}${lugar ? `, ${escapar(lugar)}` : ""}${choca ? ", choca con otra clase del profesor" : ""}. Suprimir lo quita." style="${this.posicion(b.inicio, b.fin)}">
      <span class="hs-tirador" data-borde="inicio" ${globo("Arrastre para cambiar la hora de inicio")}></span>
      <span class="hs-rango">${choca ? "⚠ " : ""}${hora(b.inicio)} – ${hora(b.fin)}</span>
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

  // ── Las capas: lo que rodea al horario (solo en el panel de la Programación) ──────────────────────

  // Las capas van en su propia capa de la grilla, debajo de los bloques: mientras se arrastra solo se redibujan los
  // bloques, y las capas cuando algo de lo que muestran cambia.
  //
  // Si el servidor devolvió el panel sin guardar (un código repetido), trae lo que ya se había decidido en el aviso
  // («decidido») y el profesor con que está guardada la sección («profesor_guardado»): sin eso, «Separar» o «Se
  // dictan juntas» se perdían, y con otro profesor sus choques pasaban por viejos y «Guardar igual» no servía.
  prepararCapas() {
    this.capas = this.leerCapas(this.capasValue)
    const decidido = this.capasValue.decidido || {}
    this.juntar = new Set(decidido.juntar || [])
    this.confirmados = new Set(decidido.confirmados || [])
    this.separar = Boolean(decidido.separar)
    this.ocultas = new Set(capasOcultas())
    this.profesorInicial = this.capasValue.profesor_guardado ?? null
    this.choquesIniciales = null
    // Si Turbo devolvió una copia de la página con la grilla ya dibujada, las capas viejas se van.
    this.diasTarget.querySelectorAll(":scope > .hs-capas").forEach((capa) => capa.remove())
    this.capasEl = document.createElement("div")
    this.capasEl.className = "hs-capas"
    this.capasEl.innerHTML = DIAS.map(() => `<div class="hs-capas-dia"></div>`).join("")
    this.diasTarget.prepend(this.capasEl)
    this.element.classList.add("con-capas")
    // El envío se escucha en el formulario, que envuelve a este controlador: una acción de Stimulus (data-action) solo
    // llega a los controladores del mismo elemento o de más arriba. Corre antes que Turbo, que respeta preventDefault.
    this.formulario = this.element.closest("form")
    this.alEnviar = (event) => this.enviar(event)
    this.formulario?.addEventListener("submit", this.alEnviar)
    this.dibujarVer()
  }

  leerCapas(datos) {
    const secciones = (lista) => (lista || []).map((s) => ({ ...s, bloques: enMinutos(s.bloques) }))
    const { profesor, semestre } = datos
    return {
      profesor: profesor ? { ...profesor, secciones: secciones(profesor.secciones) } : null,
      asignatura: secciones(datos.asignatura),
      semestre: semestre && { ...semestre, materias: (semestre.materias || []).map((m) => ({ ...m, secciones: secciones(m.secciones) })) },
      juntas: datos.juntas || [],
    }
  }

  // El buscador eligió otro profesor, o lo quitó: su capa se pide al servidor. Lo que se había decidido sobre los
  // choques era con las clases del anterior.
  async cambiarProfesor(event) {
    if (!this.capas) return
    const campo = event.target
    const id = campo.value
    this.juntar.clear()
    this.confirmados.clear()
    this.capas.profesor = null
    this.alCambiarProfesor()
    if (!id || !this.hasOcupacionValue) return
    const url = new URL(this.ocupacionValue, window.location.href)
    url.searchParams.set("profesor_id", id)
    try {
      const respuesta = await fetch(url, { headers: { Accept: "application/json" } })
      if (!respuesta.ok || campo.value !== id) return
      this.capas.profesor = this.leerCapas(await respuesta.json()).profesor
      this.alCambiarProfesor()
    } catch {
      // Sin la capa del profesor: el servidor igual revisa el choque al guardar.
    }
  }

  alCambiarProfesor() {
    this.dibujarVer()
    this.dibujar()
  }

  profesorActual() {
    return this.capas.profesor?.id ?? null
  }

  // Las que no cuentan como choque: las que ya se dictan junto con esta (salvo que se vaya a separar), las que se
  // marcaron «Se dictan juntas» y las de sus grupos, que al guardar quedan todas en uno (ChoqueDelProfesor).
  juntas() {
    const ids = new Set(this.separar ? [] : this.capas.juntas.map((j) => j.id))
    const delProfesor = this.capas.profesor?.secciones || []
    const grupos = new Set(delProfesor.filter((s) => this.juntar.has(s.id) && s.grupo).map((s) => s.grupo))
    delProfesor.forEach((s) => { if (this.juntar.has(s.id) || grupos.has(s.grupo)) ids.add(s.id) })
    return ids
  }

  // {id de la sección del profesor => { seccion, suyos, mios }}: sus bloques que pisan estos, y las claves de estos.
  choquesCon(bloques, juntas = this.juntas()) {
    const choques = new Map()
    for (const seccion of this.capas.profesor?.secciones || []) {
      if (juntas.has(seccion.id)) continue
      const suyos = seccion.bloques.filter((s) => bloques.some((m) => sePisan(m, s)))
      if (!suyos.length) continue
      const mios = bloques.filter((m) => suyos.some((s) => sePisan(m, s))).map((m) => m.clave)
      choques.set(seccion.id, { seccion, suyos, mios })
    }
    return choques
  }

  choquesActuales() {
    return this.choquesCon(this.activos().filter(valido))
  }

  // Los choques que ya había, con el horario, el profesor y el grupo guardados: esos solo se avisan. Con otro profesor,
  // todos son nuevos (como en el servidor, CapasDelHorario#choques_nuevos). Se cuentan la primera vez que la capa es
  // la del profesor guardado.
  iniciales() {
    if (this.profesorActual() !== this.profesorInicial) return new Set()
    if (!this.choquesIniciales) {
      const guardados = this.bloques.filter((b) => b.original && valido(b.original)).map((b) => b.original)
      this.choquesIniciales = new Set(this.choquesCon(guardados, new Set(this.capas.juntas.map((j) => j.id))).keys())
    }
    return this.choquesIniciales
  }

  nuevos(choques) {
    const iniciales = this.iniciales()
    return [...choques.keys()].filter((id) => !iniciales.has(id))
  }

  // Las asignaturas que se cursaron junto con esta y con las que no queda combinación: cada sección suya choca con
  // cada sección de esta asignatura (esta, con el horario de ahora, y las otras).
  sinRemedio() {
    const mias = [this.activos().filter(valido), ...this.capas.asignatura.map((s) => s.bloques)]
    return (this.capas.semestre?.materias || []).filter((m) => m.juntos > 0 && m.secciones.every((s) =>
      mias.every((bloques) => bloques.some((a) => s.bloques.some((b) => sePisan(a, b))))))
  }

  // Las otras secciones de la asignatura que tienen horario. Las del mismo profesor van en su capa.
  otrasSecciones() {
    const delProfesor = new Set((this.capas.profesor?.secciones || []).map((s) => s.id))
    return this.capas.asignatura.filter((s) => s.bloques.length && !delProfesor.has(s.id))
  }

  // Las capas, los avisos y los campos de la sección, solo si cambió algo de lo que muestran: dibujarGrilla corre en
  // cada movimiento del ratón mientras se arrastra.
  actualizarAlrededor(choques) {
    const sinRemedio = this.sinRemedio()
    const clave = JSON.stringify([this.profesorActual(), [...choques.values()].map((c) => [c.seccion.id, c.suyos, c.mios]),
      [...this.confirmados], [...this.juntar], this.separar, sinRemedio.map((m) => m.id), [...this.ocultas]])
    if (clave === this.claveAlrededor) return
    this.claveAlrededor = clave
    this.dibujarCapas(choques)
    this.dibujarAvisos(choques, sinRemedio)
    this.escribirCamposSeccion(choques)
  }

  dibujarCapas(choques) {
    const porDia = DIAS.map(() => [])
    const { profesor, semestre } = this.capas
    const delProfesor = new Set((profesor?.secciones || []).map((s) => s.id))
    const poner = (b, html) => porDia[b.dia].push(html)
    if (!this.ocultas.has("semestre")) {
      for (const m of semestre?.materias || []) {
        for (const s of m.secciones.filter((x) => !delProfesor.has(x.id))) {
          s.bloques.forEach((b) => poner(b, this.htmlCapa("semestre", b, "", `${m.nombre} (${s.codigo}) · ${this.porQueSeCursaJunto(m)}`)))
        }
      }
    }
    if (!this.ocultas.has("asignatura")) {
      for (const s of this.otrasSecciones()) {
        s.bloques.forEach((b) => poner(b, this.htmlCapa("asignatura", b, s.codigo, `Sección ${s.codigo}${s.profesor ? ` · ${s.profesor}` : ""}`)))
      }
    }
    if (profesor && !this.ocultas.has("profesor")) {
      const juntas = this.juntas()
      for (const s of profesor.secciones) {
        const nombre = `${s.asignatura} (${s.codigo})${s.escuela ? ` · ${s.escuela}` : ""}`
        const pisados = choques.get(s.id)?.suyos || []
        s.bloques.forEach((b) => {
          const estado = juntas.has(s.id) ? "junta" : pisados.includes(b) ? "choca" : null
          const nota = { junta: " · se dicta junto con esta", choca: " · choca con esta sección" }[estado] || ""
          poner(b, this.htmlCapa("profesor", b, nombre, `${profesor.nombre}: ${nombre}${nota}`, estado))
        })
      }
    }
    this.capasEl.querySelectorAll(".hs-capas-dia").forEach((dia, i) => { dia.innerHTML = porDia[i].join("") })
  }

  htmlCapa(tipo, b, rotulo, detalle, estado) {
    const texto = `${detalle} · ${nombreDia(b.dia)} de ${hora(b.inicio)} a ${hora(b.fin)}${b.aula ? ` · aula ${b.aula}` : ""}`
    const clases = ["hs-capa", `hs-capa--${tipo}`, estado && `hs-capa--${estado}`].filter(Boolean).join(" ")
    return `<div class="${clases}" style="${this.posicion(b.inicio, b.fin)}" ${globo(escapar(texto))}>${rotulo
      ? `<span class="hs-capa-rotulo">${escapar(rotulo)}</span>` : ""}</div>`
  }

  porQueSeCursaJunto(m) {
    const { rotulo, anterior } = this.capas.semestre
    return [m.semestre && rotulo, m.juntos && `la cursaron junto con esta ${m.juntos} estudiantes en ${anterior}`]
      .filter(Boolean).join(" · ")
  }

  // Los botones de las capas, arriba de la grilla: cada uno dice cuántas hay y, en su globo, qué son.
  dibujarVer() {
    if (!this.hasVerTarget) return
    const { profesor, semestre } = this.capas
    const otras = this.otrasSecciones()
    const materias = semestre?.materias || []
    const clases = (profesor?.secciones || []).filter((s) => s.bloques.length)
    const ayudaProfesor = !profesor ? "Elija el profesor para ver sus otras clases"
      : clases.length ? `Las otras clases de ${profesor.nombre} en ${profesor.periodo}, en cualquier escuela, rayadas`
        : `${profesor.nombre} no tiene otras clases con horario en ${profesor.periodo}`
    const ayudaOtras = otras.length ? "Las otras secciones de la asignatura, con borde punteado" : "La asignatura no tiene otras secciones con horario"
    const cursadas = semestre?.anterior ? `las que se cursaron junto con esta en ${semestre.anterior} (5 estudiantes o más)` : ""
    const delSemestre = semestre?.rotulo?.match(/^(Semestre|Año) /) ? `las otras asignaturas del ${semestre.rotulo.toLowerCase()}` : ""
    const ayudaSemestre = materias.length ? `${enLista([delSemestre, cursadas].filter(Boolean))}, en un tono suave`.replace(/^./, (c) => c.toUpperCase())
      : "Ninguna asignatura del semestre, ni de las que se cursan junto con esta, tiene horario todavía"
    this.verTarget.innerHTML = `<span class="hs-ver-titulo">Ver</span>${[
      this.htmlChip("profesor", "Profesor", clases.length, ayudaProfesor),
      this.htmlChip("asignatura", "Otras secciones", otras.length, ayudaOtras),
      this.htmlChip("semestre", semestre?.rotulo || "Semestre", materias.length, ayudaSemestre),
    ].join("")}`
  }

  // Sin nada que mostrar, el botón queda apagado con aria-disabled y no con disabled: así su globo sigue saliendo.
  htmlChip(capa, rotulo, cuantas, ayuda) {
    return `<button type="button" class="hs-ver-chip" data-capa="${capa}" aria-pressed="${!this.ocultas.has(capa)}"
        ${cuantas ? "" : `aria-disabled="true"`} data-action="horario-semanal#alternarCapa" ${globo(escapar(ayuda), "bottom")}>
      <span class="hs-muestra hs-muestra--${capa}"></span>${escapar(rotulo)} <span class="hs-ver-cuenta">${cuantas || 0}</span>
    </button>`
  }

  alternarCapa(event) {
    const chip = event.currentTarget
    if (chip.getAttribute("aria-disabled") === "true") return
    const capa = chip.dataset.capa
    if (!this.ocultas.delete(capa)) this.ocultas.add(capa)
    chip.setAttribute("aria-pressed", String(!this.ocultas.has(capa)))
    guardarCapasOcultas(this.ocultas)
    this.actualizarAlrededor(this.choquesActuales())
  }

  // El aviso ámbar del choque, con sus tres salidas, y debajo lo que ya se decidió y lo que no tiene combinación.
  dibujarAvisos(choques, sinRemedio) {
    if (!this.hasAvisosTarget) return
    const { profesor, semestre } = this.capas
    const iniciales = this.iniciales()
    const lista = [...choques.values()]
    const abiertos = lista.filter((c) => !this.confirmados.has(c.seccion.id))
    const aceptados = lista.filter((c) => this.confirmados.has(c.seccion.id))
    const nombre = (s) => escapar(`${s.asignatura} (${s.codigo})`)
    const horas = (bloques) => bloques.map((b) => `${nombreDia(b.dia)} de ${hora(b.inicio)} a ${hora(b.fin)}`).join(" y ")
    const boton = (texto, accion, extra = "") =>
      `<button type="button" class="btn btn-sm hs-aviso-boton" data-action="horario-semanal#${accion}" ${extra}>${texto}</button>`
    const linea = (clase, icono, texto, accion = "") =>
      `<div class="hs-aviso hs-aviso--${clase}"><i class="fas fa-${icono}"></i><span>${texto}</span>${accion}</div>`
    const avisos = []
    if (abiertos.length) {
      const filas = abiertos.map(({ seccion, suyos }) => `<div class="hs-aviso-linea">
          <span>${nombre(seccion)}${seccion.escuela ? ` · ${escapar(seccion.escuela)}` : ""}: ${horas(suyos)}${iniciales.has(seccion.id)
            ? ` <span class="hs-aviso-nota">(ya chocaba)</span>` : ""}</span>
          ${seccion.escuela ? "" : boton("Se dictan juntas", "juntarCon", `data-seccion="${seccion.id}"`)}
        </div>`).join("")
      avisos.push(`<div class="hs-aviso hs-aviso--choque">
        <div class="hs-aviso-titulo"><i class="fas fa-triangle-exclamation"></i> ${escapar(profesor.nombre)} ya tiene clase a esa hora</div>
        ${filas}
        <div class="hs-aviso-acciones">${boton("Mover el bloque", "moverBloque")}${boton("Guardar igual", "guardarIgual")}</div>
      </div>`)
    }
    if (aceptados.length) {
      avisos.push(linea("aceptado", "triangle-exclamation", `Se guardará aunque choca con ${enLista(aceptados.map((c) => nombre(c.seccion)))}.`,
        boton("Deshacer", "deshacerGuardarIgual")))
    }
    const guardadas = enLista(this.capas.juntas.map((j) => escapar(j.texto)))
    if (guardadas && this.separar) {
      avisos.push(linea("junta", "link-slash", `Al guardar, deja de dictarse junto con ${guardadas}.`, boton("Deshacer", "deshacerSeparar")))
    } else if (guardadas) {
      avisos.push(linea("junta", "link", `Se dicta junto con ${guardadas}.`, boton("Separar", "separarDictado")))
    }
    if (this.juntar.size) {
      const nuevas = (profesor?.secciones || []).filter((s) => this.juntar.has(s.id)).map(nombre)
      avisos.push(linea("junta", "link", `Al guardar, se dictará junto con ${enLista(nuevas)}.`, boton("Deshacer", "deshacerJuntar")))
    }
    sinRemedio.forEach((m) => avisos.push(linea("info", "circle-info", `Con ${escapar(m.nombre)} no queda combinación: cada una de sus ` +
      `secciones choca con cada sección de esta asignatura, y en ${escapar(semestre.anterior)} la cursaron junto con esta ${m.juntos} estudiantes.`)))
    this.avisosTarget.innerHTML = avisos.join("")
  }

  // Lo que deciden los avisos viaja con la sección: section[juntar_con][], section[separar_del_dictado] y
  // section[choque_confirmado][], con cada sección con que se aceptó el choque (ChoqueDelProfesor). «section» sale
  // del prefijo del horario.
  escribirCamposSeccion(choques) {
    if (!this.hasCamposSeccionTarget) return
    const seccion = this.prefijoValue.replace(/\[timetable_attributes\]$/, "")
    const campo = (nombre, valor) => `<input type="hidden" name="${seccion}${nombre}" value="${escapar(valor)}">`
    const aceptados = this.nuevos(choques).filter((id) => this.confirmados.has(id))
    this.camposSeccionTarget.innerHTML = [...this.juntar].map((id) => campo("[juntar_con][]", id)).join("") +
      (this.separar ? campo("[separar_del_dictado]", "1") : "") +
      aceptados.map((id) => campo("[choque_confirmado][]", id)).join("")
  }

  // Para el lector de pantalla: el aviso no se lee solo, así que cada cambio dice si quedó chocando.
  textoDelChoque() {
    if (!this.capas) return ""
    const abiertos = [...this.choquesActuales().values()].filter((c) => !this.confirmados.has(c.seccion.id))
    if (!abiertos.length) return ""
    return `${this.capas.profesor.nombre} ya tiene clase a esa hora: ${enLista(abiertos.map((c) => `${c.seccion.asignatura} (${c.seccion.codigo})`))}.`
  }

  // Crear o Guardar con un choque nuevo sin decidir: no se envía, y el aviso se sacude para que se vea.
  enviar(event) {
    const choques = this.choquesActuales()
    const iniciales = this.iniciales()
    if (!this.hasAvisosTarget || ![...choques.keys()].some((id) => !iniciales.has(id) && !this.confirmados.has(id))) return
    event.preventDefault()
    const avisos = this.avisosTarget
    avisos.classList.remove("hs-avisos--brinca")
    void avisos.offsetWidth // para que la animación corra otra vez
    avisos.classList.add("hs-avisos--brinca")
    // Se sacude una vez: si la clase se quedaba, el aviso volvía a sacudirse cada vez que se redibujaba.
    clearTimeout(this.finDelBrinco)
    this.finDelBrinco = setTimeout(() => avisos.classList.remove("hs-avisos--brinca"), 1500)
    avisos.scrollIntoView({ block: "nearest", behavior: "smooth" })
    avisos.focus({ preventScroll: true })
    this.anuncioTarget.textContent = `No se guardó: ${this.capas.profesor.nombre} ya tiene clase a esa hora. Elija mover el ` +
      "bloque, «Se dictan juntas» o «Guardar igual»."
  }

  juntarCon(event) {
    const id = Number(event.currentTarget.dataset.seccion)
    const s = this.capas.profesor?.secciones.find((x) => x.id === id)
    if (!s) return
    this.juntar.add(id)
    this.confirmados.delete(id)
    this.cambioDeCapas(`Al guardar, ${s.asignatura} (${s.codigo}) queda dictándose junto con esta sección.`)
  }

  deshacerJuntar() {
    this.juntar.clear()
    this.cambioDeCapas("Ya no se marcan como dictadas juntas.")
  }

  guardarIgual() {
    this.choquesActuales().forEach((_, id) => this.confirmados.add(id))
    this.cambioDeCapas("Se guardará aunque choca.")
  }

  deshacerGuardarIgual() {
    this.confirmados.clear()
    this.cambioDeCapas("Hay que decidir otra vez qué hacer con el choque.")
  }

  separarDictado() {
    this.separar = true
    this.cambioDeCapas("Al guardar, deja de dictarse junto con las otras.")
  }

  deshacerSeparar() {
    this.separar = false
    this.cambioDeCapas("Se sigue dictando junto con las otras.")
  }

  // El primer bloque que choca queda elegido en la grilla, con las clases del profesor a la vista.
  moverBloque() {
    const clave = [...this.choquesActuales().values()].flatMap((c) => c.mios)[0]
    const b = clave && this.bloque(clave)
    if (!b) return
    if (this.ocultas.delete("profesor")) {
      guardarCapasOcultas(this.ocultas)
      this.dibujarVer()
    }
    this.seleccionado = clave
    this.dibujar()
    this.enfocarBloque(clave)
    this.pista(`Arrastre el bloque del ${nombreDia(b.dia)} a una hora libre, o cámbiele la hora en la lista: lo rayado es ` +
      `donde ${this.capas.profesor.nombre} ya tiene clase.`)
  }

  cambioDeCapas(mensaje) {
    this.dibujar()
    this.avisosTarget.focus({ preventScroll: true })
    this.anuncioTarget.textContent = mensaje
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
    this.conPista = false
    this.guiaTarget.textContent = texto || this.guiaInicial
    this.guiaTarget.classList.toggle("hs-guia--activa", Boolean(texto))
  }

  // Una indicación en el lugar de la guía, sin la marca de gesto a medias: con «hs-guia--activa», el Esc no cerraría el
  // panel (seccion_panel_controller.js). Se va con el próximo cambio.
  pista(texto) {
    this.guiaTarget.textContent = texto
    this.guiaTarget.classList.remove("hs-guia--activa")
    this.conPista = true
    this.anuncioTarget.textContent = texto
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
