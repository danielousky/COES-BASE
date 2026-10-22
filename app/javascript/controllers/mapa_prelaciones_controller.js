import { Controller } from "@hotwired/stimulus"

// Mapa de prelaciones de una escuela (vista Estructura del plan de estudio).
// Columnas por semestre; cada flecha va del prerrequisito a la materia que lo exige.
// Las reglas viven en el servidor: la advertencia de cada prelación, los ciclos y la oferta del estudiante
// (Grade#asignaturas_ofertables_segun_dependencia). Aquí sólo se dibuja y, en modo estudiante, se simula.
export default class extends Controller {
  static targets = ["board", "svg", "panel", "banner", "buscar", "solo", "vistaPlan", "vistaEstudiante", "lista"]
  static values = {
    datos: Object,
    puedeEditar: Boolean,
    porDependencia: Boolean,
    ofertaUrl: String,
    estudiante: Object
  }

  connect() {
    this.materias = new Map(this.datosValue.materias.map(m => [m.id, m]))
    this.prelaciones = this.datosValue.prelaciones
    this.vista = "plan"
    this.sel = null
    this.q = ""
    this.estudiante = null
    this.aprobadas = new Set()
    this.ofertablesServidor = null
    this.periodo = null
    // Simulador de inscripción: el estudiante viene del servidor y no se cambia desde aquí
    this.fijo = !!this.estudianteValue.ci
    if (this.fijo) { this.vista = "est"; this.usarEstudiante(this.estudianteValue) }
    this.alRedimensionar = () => { clearTimeout(this.tRedim); this.tRedim = setTimeout(() => this.render(), 150) }
    window.addEventListener("resize", this.alRedimensionar)
    this.render()
  }

  disconnect() {
    window.removeEventListener("resize", this.alRedimensionar)
  }

  // --- acciones de la barra ---

  verPlan() { this.vista = "plan"; this.sel = null; this.render() }
  verEstudiante() { this.vista = "est"; this.sel = null; this.render() }
  filtrar() { this.q = this.buscarTarget.value.trim().toLowerCase(); this.render() }
  cambiarSolo() { this.render() }

  tocar(event) {
    const card = event.target.closest(".mp-card")
    if (!card) return
    const id = +card.dataset.id
    if (this.vista === "est" && this.estudiante) {
      this.aprobadas.has(id) ? this.aprobadas.delete(id) : this.aprobadas.add(id)
      this.ofertablesServidor = null // a partir de aquí es simulación
      this.sel = id
    } else {
      this.sel = this.sel === id ? null : id
    }
    this.render()
  }

  teclear(event) {
    if ((event.key === "Enter" || event.key === " ") && event.target.classList.contains("mp-card")) {
      event.preventDefault()
      event.target.click()
    }
  }

  // --- consultas sobre el grafo ---

  nombre(id) { return titulo(this.materias.get(id)?.nombre || `#${id}`) }
  prereqs(id) { return this.prelaciones.filter(l => l.materia === id).map(l => l.previa) }
  abre(id) { return this.prelaciones.filter(l => l.previa === id).map(l => l.materia) }
  cadena(id, siguiente) {
    const out = new Set(), pila = [...siguiente.call(this, id)]
    while (pila.length) { const x = pila.pop(); if (!out.has(x)) { out.add(x); pila.push(...siguiente.call(this, x)) } }
    return out
  }
  ofertable(id) {
    if (this.ofertablesServidor) return this.ofertablesServidor.has(id)
    const m = this.materias.get(id)
    return !m.externa && !this.aprobadas.has(id) && this.prereqs(id).every(p => this.aprobadas.has(p))
  }
  // Con período: lo real viene del servidor (OfertaInscripcion); al simular, cumple prelaciones y tiene sección
  apareceEnPeriodo(id) {
    if (this.ofertablesServidor) return this.periodo.ofertadas.has(id)
    return this.ofertable(id) && this.periodo.programadas.has(id)
  }
  alertas() { return this.prelaciones.filter(l => l.advertencia) }

  // --- dibujo ---

  render() {
    this.vistaPlanTarget.setAttribute("aria-pressed", this.vista === "plan")
    this.vistaEstudianteTarget.setAttribute("aria-pressed", this.vista === "est")
    this.renderBanner()
    this.renderBoard()
    this.renderPanel()
  }

  visibles() {
    const enPrelaciones = new Set()
    this.prelaciones.forEach(l => { enPrelaciones.add(l.materia); enPrelaciones.add(l.previa) })
    const solo = this.soloTarget.checked
    return this.datosValue.materias.filter(m =>
      (!solo || enPrelaciones.has(m.id) || (this.vista === "est" && this.aprobadas.has(m.id))) &&
      (!this.q || `${m.nombre} ${m.codigo}`.toLowerCase().includes(this.q)))
  }

  renderBoard() {
    const board = this.boardTarget
    board.querySelectorAll(".mp-col").forEach(c => c.remove())
    const columnas = new Map()
    this.visibles().forEach(m => {
      const k = m.externa ? 1000 : (m.semestre || 999)
      if (!columnas.has(k)) columnas.set(k, [])
      columnas.get(k).push(m)
    })
    const conAlerta = new Set()
    this.alertas().forEach(l => { conAlerta.add(l.materia); conAlerta.add(l.previa) })
    let necesita = new Set(), abre = new Set()
    const resaltar = this.sel && this.vista === "plan"
    if (resaltar) { necesita = this.cadena(this.sel, this.prereqs); abre = this.cadena(this.sel, this.abre) }
    board.classList.toggle("mp-dim", !!resaltar)

    ;[...columnas.keys()].sort((a, b) => a - b).forEach(k => {
      const lista = columnas.get(k).sort((a, b) => a.codigo.localeCompare(b.codigo))
      const col = document.createElement("div")
      col.className = "mp-col" + (k >= 999 ? " mp-col-ancha" : "")
      const rotulo = k === 1000 ? "Otras escuelas" : k === 999 ? "Electivas" : `${k}.º semestre`
      col.innerHTML = `<h3>${rotulo}<span>${lista.length}</span></h3>`
      lista.forEach(m => col.appendChild(this.tarjeta(m, { conAlerta, necesita, abre })))
      board.appendChild(col)
    })
    requestAnimationFrame(() => this.dibujarFlechas(necesita, abre))
  }

  tarjeta(m, { conAlerta, necesita, abre }) {
    const c = document.createElement("div")
    const clases = ["mp-card"]
    let pie
    if (this.vista === "plan") {
      if (conAlerta.has(m.id)) clases.push("mp-err")
      if (m.id === this.sel) clases.push("mp-sel")
      if (necesita.has(m.id)) clases.push("mp-need")
      if (abre.has(m.id)) clases.push("mp-opens")
      pie = `<span>necesita ${this.prereqs(m.id).length}</span><span>abre ${this.abre(m.id).length}</span>`
    } else if (this.estudiante) {
      const aprobada = this.aprobadas.has(m.id), oferta = !aprobada && this.ofertable(m.id)
      if (this.periodo && !aprobada && this.periodo.inscritas.has(m.id)) {
        clases.push("mp-ins"); pie = `<span class="mp-tag mp-tag-ins">inscrita</span>`
      } else if (this.periodo && oferta && !this.apareceEnPeriodo(m.id)) {
        clases.push("mp-nop"); pie = `<span class="mp-tag">cumple, sin sección</span>`
      } else {
        clases.push(aprobada ? "mp-ok" : oferta ? "mp-av" : "mp-lock")
        const sinCupo = oferta && this.periodo && this.ofertablesServidor && this.periodo.sinCupo.has(m.id)
        pie = aprobada ? "" : oferta ? `<span class="mp-tag mp-tag-av">${this.periodo ? "le aparece" : "se le oferta"}</span>${sinCupo ? `<span class="mp-tag mp-tag-bad">sin cupo</span>` : ""}` : `<span class="mp-tag">bloqueada</span>`
      }
    } else {
      pie = ""
    }
    if (m.id === this.sel && this.vista === "est") clases.push("mp-sel")
    c.className = clases.join(" ")
    c.tabIndex = 0
    c.dataset.id = m.id
    c.setAttribute("role", "button")
    c.innerHTML = `<div class="mp-code"><span>${esc(m.codigo)}</span><span>${m.creditos ?? ""} UC</span></div>` +
      `<div class="mp-nm">${esc(titulo(m.nombre))}</div><div class="mp-meta">${pie}</div>`
    return c
  }

  dibujarFlechas(necesita, abre) {
    const board = this.boardTarget, svg = this.svgTarget
    const br = board.getBoundingClientRect()
    svg.setAttribute("width", board.scrollWidth)
    svg.setAttribute("height", board.scrollHeight)
    const pos = new Map()
    board.querySelectorAll(".mp-card").forEach(c => {
      const r = c.getBoundingClientRect()
      pos.set(+c.dataset.id, { l: r.left - br.left, r: r.right - br.left, y: r.top - br.top + r.height / 2 })
    })
    const colores = { linea: "#9aa6b2", bad: "#c23b2f", need: "#b86e00", opens: "#23855a" }
    let html = `<defs>${Object.entries(colores).map(([k, c]) =>
      `<marker id="mp-m-${k}" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,0 L8,4 L0,8 z" fill="${c}"/></marker>`).join("")}</defs>`
    const resaltar = this.sel && this.vista === "plan"
    this.prelaciones.forEach(l => {
      const p = pos.get(l.previa), q = pos.get(l.materia)
      if (!p || !q) return
      // En modo estudiante importa qué se oferta, no si la prelación parece al revés
      let tipo = l.advertencia && this.vista === "plan" ? "bad" : "linea", visible = true
      if (resaltar) {
        const enNecesita = (l.materia === this.sel || necesita.has(l.materia)) && necesita.has(l.previa)
        const enAbre = (l.previa === this.sel || abre.has(l.previa)) && abre.has(l.materia)
        if (enNecesita) tipo = l.advertencia ? "bad" : "need"
        else if (enAbre) tipo = l.advertencia ? "bad" : "opens"
        else visible = false
      }
      let d
      if (p.r < q.l - 4) {
        const mx = (p.r + q.l) / 2
        d = `M${p.r},${p.y} C${mx},${p.y} ${mx},${q.y} ${q.l - 2},${q.y}`
      } else {
        const elevar = 60 + Math.abs(p.l - q.l) * 0.15
        d = `M${p.l},${p.y} C${p.l - elevar},${p.y} ${q.l - elevar},${q.y} ${q.l - 2},${q.y}`
      }
      html += `<path d="${d}" fill="none" stroke="${colores[tipo]}" stroke-width="${tipo === "linea" ? 1.4 : 2.4}" opacity="${visible ? 1 : 0.08}" marker-end="url(#mp-m-${tipo})"/>`
    })
    svg.innerHTML = html
  }

  renderBanner() {
    const b = this.bannerTarget
    if (this.vista === "est") {
      b.className = "mp-banner mp-banner-est"
      if (!this.porDependenciaValue) {
        b.innerHTML = `<b>Ver como estudiante</b><span>Este plan no filtra la oferta por prelaciones: al inscribirse, el estudiante ve todas las materias ofertadas.</span>`
        return
      }
      const buscador = `<form class="mp-ci" data-action="submit->mapa-prelaciones#cargarEstudiante"><input type="search" name="ci" placeholder="Cédula del estudiante" aria-label="Cédula del estudiante" value="${esc(this.estudiante?.ci || "")}"><button class="mp-btn mp-btn-pri" type="submit">Cargar</button></form>`
      if (!this.estudiante) {
        b.innerHTML = `<b>Ver como estudiante</b><span>Escribe una cédula para ver qué se le ofertaría con las prelaciones de hoy.</span>${buscador}`
        return
      }
      const fuente = this.ofertablesServidor ? "según COES" : "simulación: tocaste materias para marcarlas o desmarcarlas como aprobadas"
      const ocultas = this.soloTarget.checked ? " Incluye materias sin prelaciones, que el filtro oculta." : ""
      let resumen
      if (this.periodo) {
        const n = this.datosValue.materias.filter(m => !this.aprobadas.has(m.id) && this.apareceEnPeriodo(m.id)).length
        resumen = `${this.aprobadas.size} aprobadas · en ${esc(this.periodo.nombre)} le aparecerían ${n} materias de su escuela (${fuente}).${ocultas}`
      } else {
        const n = this.datosValue.materias.filter(m => !this.aprobadas.has(m.id) && this.ofertable(m.id)).length
        resumen = `${this.aprobadas.size} aprobadas · se le ofertarían ${n} (${fuente}).${ocultas}`
      }
      b.innerHTML = `<b>${esc(this.estudiante.estudiante)}</b><span>${resumen}</span>${this.fijo ? "" : buscador}` +
        (this.ofertablesServidor ? "" : `<button class="mp-btn" type="button" data-action="mapa-prelaciones#recargarEstudiante">Volver a lo real</button>`)
      return
    }
    const n = this.alertas().length
    if (n) {
      b.className = "mp-banner mp-banner-bad"
      b.innerHTML = `<b>${n} ${n === 1 ? "prelación parece" : "prelaciones parecen"} al revés</b><span>Las flechas rojas apuntan hacia atrás o invierten un par I/II. Revísalas en el panel de la derecha.</span>`
    } else {
      b.className = "mp-banner mp-banner-ok"
      b.innerHTML = `<b>Plan sin alertas</b><span>${this.prelaciones.length} prelaciones, todas del prerrequisito hacia adelante.</span>`
    }
  }

  renderPanel() {
    const p = this.panelTarget
    if (this.vista === "est") return this.renderPanelEstudiante(p)
    if (!this.sel) return this.renderPanelAlertas(p)

    const m = this.materias.get(this.sel), pr = this.prereqs(this.sel), ab = this.abre(this.sel)
    const chip = (l, otro, clase, quitar) =>
      `<span class="mp-chip ${l.advertencia ? "mp-chip-bad" : clase}">${esc(this.nombre(otro))}` +
      (quitar && this.puedeEditarValue ? `<button type="button" aria-label="Quitar" data-action="mapa-prelaciones#quitar" data-id="${l.id}">×</button>` : "") + `</span>`
    const delSel = this.prelaciones.filter(l => l.materia === this.sel)
    const haciaSel = this.prelaciones.filter(l => l.previa === this.sel)
    p.innerHTML = `<div><div class="mp-sub">${esc(m.codigo)} · ${semestre(m)} · ${m.creditos ?? "?"} UC</div><h2>${esc(this.nombre(this.sel))}</h2></div>
      <div class="mp-sent mp-sent-need"><span class="mp-k">Para cursarla hay que aprobar</span>${pr.length ? `<div class="mp-chips">${delSel.map(l => chip(l, l.previa, "mp-chip-need", true)).join("")}</div>` : `<span class="mp-empty">Nada. Se puede cursar sin prelaciones.</span>`}</div>
      <div class="mp-sent mp-sent-opens"><span class="mp-k">Al aprobarla se abre</span>${ab.length ? `<div class="mp-chips">${haciaSel.map(l => chip(l, l.materia, "mp-chip-opens", false)).join("")}</div>` : `<span class="mp-empty">No abre ninguna otra materia.</span>`}</div>
      ${this.puedeEditarValue && !m.externa ? this.formularioAgregar(m, pr) : ""}
      <div class="mp-links"><a href="/admin/subject/${m.id}">Ver ficha de la asignatura</a><button class="mp-btn" type="button" data-action="mapa-prelaciones#cerrar">Volver a las alertas</button></div>`
  }

  formularioAgregar(m, pr) {
    const opciones = this.datosValue.materias.filter(x => x.id !== m.id && !pr.includes(x.id))
      .map(x => `<option value="${esc(titulo(x.nombre))} · ${esc(x.codigo)}"></option>`).join("")
    return `<div class="mp-add"><label for="mp-nuevo">¿Qué más hay que aprobar para cursar ${esc(this.nombre(m.id))}?</label>
      <input id="mp-nuevo" list="mp-opciones" placeholder="Escribe el nombre o el código" data-action="change->mapa-prelaciones#elegirPrevia">
      <datalist id="mp-opciones">${opciones}</datalist><div data-mapa-prelaciones-confirmacion></div></div>`
  }

  renderPanelAlertas(p) {
    const alertas = this.alertas()
    p.innerHTML = `<h2>Alertas del plan</h2>` + (alertas.length
      ? `<p class="mp-sent">Prelaciones que parecen cargadas al revés. Revísalas una por una${this.puedeEditarValue ? " y corrígelas con un clic" : ""}.</p><div class="mp-alerts">${alertas.map(l => `
          <div class="mp-alert"><span class="mp-why">${esc(l.advertencia)}</span>
            <span>Hoy dice: para cursar <b>${esc(this.nombre(l.materia))}</b> hay que aprobar <b>${esc(this.nombre(l.previa))}</b></span>
            <div class="mp-row"><button class="mp-btn" type="button" data-action="mapa-prelaciones#verMateria" data-id="${l.materia}">Ver en el mapa</button>
            ${this.puedeEditarValue ? `<button class="mp-btn mp-btn-fix" type="button" data-action="mapa-prelaciones#invertir" data-id="${l.id}">Invertir</button>` : ""}</div>
          </div>`).join("")}</div>`
      : `<p class="mp-sent">No hay prelaciones hacia atrás ni pares I/II invertidos. Toca cualquier materia para ver qué necesita y qué abre.</p>`)
  }

  renderPanelEstudiante(p) {
    if (this.hasListaTarget && this.ofertablesServidor && !this.sel) {
      p.innerHTML = this.listaTarget.innerHTML
      return
    }
    if (!this.estudiante || !this.sel) {
      p.innerHTML = `<h2>¿Qué se le ofertaría?</h2><p class="mp-sent">En verde, las materias que el estudiante vería al inscribirse: no las ha aprobado y ya cumplió todas sus prelaciones. Toca una bloqueada para saber qué le falta; al tocarla también se marca o desmarca como aprobada para simular.</p>` +
        (this.hasListaTarget ? `<p class="mp-sent">Estás simulando: la lista real de su oferta vuelve con «Volver a lo real».</p>` : "")
      return
    }
    const m = this.materias.get(this.sel)
    const falta = this.prereqs(this.sel).filter(x => !this.aprobadas.has(x))
    p.innerHTML = `<div><div class="mp-sub">${esc(m.codigo)} · ${semestre(m)}</div><h2>${esc(this.nombre(this.sel))}</h2></div>` +
      (this.aprobadas.has(this.sel) ? `<p class="mp-sent">Marcada como aprobada.</p>`
        : falta.length ? `<div class="mp-sent mp-sent-need"><span class="mp-k">Le falta aprobar</span><div class="mp-chips">${falta.map(x => `<span class="mp-chip mp-chip-need">${esc(this.nombre(x))}</span>`).join("")}</div></div>`
          : this.periodo && this.periodo.inscritas.has(this.sel) ? `<p class="mp-sent">Ya la inscribió en ${esc(this.periodo.nombre)}.</p>`
            : this.periodo && !this.apareceEnPeriodo(this.sel) ? `<p class="mp-sent">Cumple todas las prelaciones, pero en ${esc(this.periodo.nombre)} no tiene sección: no le aparece.</p>`
              : `<p class="mp-sent">${this.periodo ? `Le aparece en ${esc(this.periodo.nombre)}` : "Se le oferta"}: cumple todas las prelaciones.</p>`)
  }

  // --- acciones del panel ---

  cerrar() { this.sel = null; this.render() }
  verMateria(event) { this.sel = +event.currentTarget.dataset.id; this.render() }

  elegirPrevia(event) {
    const codigo = event.target.value.split(" · ").pop()
    const previa = this.datosValue.materias.find(x => x.codigo === codigo)
    if (!previa) return
    const materia = this.materias.get(this.sel)
    const caja = this.panelTarget.querySelector("[data-mapa-prelaciones-confirmacion]")
    const circular = this.cadena(previa.id, this.prereqs).has(materia.id)
    caja.innerHTML = `<div class="mp-confirm${circular ? " mp-confirm-warn" : ""}">
      <span>Hay que aprobar <b>${esc(titulo(previa.nombre))}</b> para cursar <b>${esc(titulo(materia.nombre))}</b>. ¿Es correcto?</span>
      ${circular ? `<span class="mp-w">No se puede: ${esc(titulo(previa.nombre))} ya exige, directa o indirectamente, ${esc(titulo(materia.nombre))}.</span>` : ""}
      <div class="mp-btns"><button class="mp-btn mp-btn-pri" type="button" ${circular ? "disabled" : ""} data-action="mapa-prelaciones#agregar" data-previa="${previa.id}">Sí, agregar prelación</button>
      <button class="mp-btn" type="button" data-action="mapa-prelaciones#cerrarConfirmacion">Cancelar</button></div></div>`
  }

  cerrarConfirmacion() { this.renderPanel() }

  async agregar(event) {
    const boton = event.currentTarget
    const cuerpo = { subject_link: { prelate_subject_id: this.sel, depend_subject_id: +boton.dataset.previa } }
    if (boton.dataset.confirmar) cuerpo.confirmar = "1"
    const r = await this.enviar("POST", "/subject_links.json", cuerpo)
    if (r.status === 409) return this.pedirConfirmacion(boton, r.json.advertencia)
    if (!r.ok) return this.aviso(r.json.error || "No se pudo guardar")
    this.prelaciones.push(r.json)
    this.aviso(`Guardada: para cursar ${this.nombre(r.json.materia)} hay que aprobar ${this.nombre(r.json.previa)}`)
    this.render()
  }

  async invertir(event) {
    const boton = event.currentTarget
    const l = this.prelaciones.find(x => x.id === +boton.dataset.id)
    const pregunta = `Invertir: para cursar ${this.nombre(l.previa)} habrá que aprobar ${this.nombre(l.materia)}. ¿Es correcto?`
    if (!boton.dataset.confirmar && !window.confirm(pregunta)) return
    const r = await this.enviar("PATCH", `/subject_links/${l.id}/invertir.json`, boton.dataset.confirmar ? { confirmar: "1" } : {})
    if (r.status === 409) return this.pedirConfirmacion(boton, r.json.advertencia)
    if (!r.ok) return this.aviso(r.json.error || "No se pudo invertir")
    Object.assign(l, r.json)
    this.aviso(`Corregida: para cursar ${this.nombre(l.materia)} hay que aprobar ${this.nombre(l.previa)}`)
    this.render()
  }

  async quitar(event) {
    const l = this.prelaciones.find(x => x.id === +event.currentTarget.dataset.id)
    if (!window.confirm(`¿Quitar la prelación? ${this.nombre(l.materia)} ya no exigirá ${this.nombre(l.previa)}.`)) return
    const r = await this.enviar("DELETE", `/subject_links/${l.id}.json`)
    if (!r.ok) return this.aviso(r.json.error || "No se pudo quitar")
    this.prelaciones = this.prelaciones.filter(x => x.id !== l.id)
    this.aviso(`Quitada: ${this.nombre(l.materia)} ya no exige ${this.nombre(l.previa)}`)
    this.render()
  }

  // El servidor advierte que parece al revés: se explica y se pide confirmar una vez más
  pedirConfirmacion(boton, advertencia) {
    const caja = document.createElement("div")
    caja.className = "mp-confirm mp-confirm-warn"
    caja.innerHTML = `<span class="mp-w">Atención: ${esc(advertencia)}. Normalmente el prerrequisito va antes; confírmalo sólo si es una excepción del plan.</span>
      <div class="mp-btns"><button class="mp-btn mp-btn-pri" type="button">Sí, es correcto</button><button class="mp-btn" type="button">Cancelar</button></div>`
    const [si, no] = caja.querySelectorAll("button")
    si.dataset.action = boton.dataset.action
    Object.entries(boton.dataset).forEach(([k, v]) => { if (k !== "action") si.dataset[k] = v })
    si.dataset.confirmar = "1"
    no.addEventListener("click", () => caja.remove())
    boton.closest(".mp-confirm, .mp-alert").after(caja)
  }

  async cargarEstudiante(event) {
    event.preventDefault()
    const ci = new FormData(event.target).get("ci").toString().trim()
    if (!ci) return
    const r = await this.enviar("GET", `${this.ofertaUrlValue}?ci=${encodeURIComponent(ci)}`)
    if (!r.ok) return this.aviso(r.json.error || "No se encontró el estudiante")
    this.usarEstudiante(r.json)
    this.render()
  }

  recargarEstudiante() {
    this.usarEstudiante(this.estudiante)
    this.render()
  }

  usarEstudiante(json) {
    this.estudiante = json
    this.aprobadas = new Set(json.aprobadas)
    this.ofertablesServidor = new Set(json.ofertables)
    this.periodo = json.periodo && { nombre: json.periodo.nombre, ofertadas: new Set(json.periodo.ofertadas),
      programadas: new Set(json.periodo.programadas), inscritas: new Set(json.periodo.inscritas), sinCupo: new Set(json.periodo.sin_cupo) }
    this.sel = null
  }

  async enviar(metodo, url, cuerpo) {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    const opciones = { method: metodo, headers: { "Accept": "application/json", "X-CSRF-Token": token }, credentials: "same-origin" }
    if (cuerpo && metodo !== "GET") {
      opciones.headers["Content-Type"] = "application/json"
      opciones.body = JSON.stringify(cuerpo)
    }
    try {
      const resp = await fetch(url, opciones)
      const json = await resp.json().catch(() => ({}))
      return { ok: resp.ok, status: resp.status, json }
    } catch (e) {
      return { ok: false, status: 0, json: { error: "Sin conexión con COES" } }
    }
  }

  aviso(mensaje) {
    let t = this.element.querySelector(".mp-toast")
    if (!t) { t = document.createElement("div"); t.className = "mp-toast"; t.setAttribute("role", "status"); this.element.appendChild(t) }
    t.textContent = mensaje
    t.hidden = false
    clearTimeout(this.tAviso)
    this.tAviso = setTimeout(() => { t.hidden = true }, 3500)
  }
}

const MENORES = new Set(["de", "del", "la", "las", "los", "y", "en", "a", "al", "con", "para", "el", "e"])
const ROMANO = /^\(?(i|ii|iii|iv|v|vi|vii|viii|ix|x)\)?$/

function titulo(texto) {
  return String(texto).toLowerCase().split(/\s+/).map((w, i) =>
    ROMANO.test(w) ? w.toUpperCase() : (i && MENORES.has(w) ? w : w.charAt(0).toUpperCase() + w.slice(1))).join(" ")
}

function esc(texto) {
  return String(texto).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]))
}

function semestre(m) {
  if (m.externa) return "otra escuela"
  return m.semestre ? `${m.semestre}.º semestre` : "electiva"
}
