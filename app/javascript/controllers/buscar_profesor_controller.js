import { Controller } from "@hotwired/stimulus"

// El profesor de una sección, buscado mientras se escribe: nombre, apellido o cédula, sin importar los acentos
// (Programacion::SeccionesController#profesores). Al elegirlo, su id queda en el campo oculto. Flechas y Enter
// eligen sin el ratón; Esc o salir sin elegir devuelven el que estaba; borrar el texto deja la sección sin profesor.
const escapar = (texto) => String(texto).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c])

export default class extends Controller {
  static targets = ["id", "texto", "resultados"]
  static values = { url: String }

  connect() {
    this.elegido = this.textoTarget.value
    this.lista = []
    this.indice = -1
  }

  buscar() {
    clearTimeout(this.espera)
    const consulta = this.textoTarget.value.trim()
    if (consulta === "") {
      this.idTarget.value = ""
      this.elegido = ""
      return this.limpiar()
    }
    if (consulta.length < 2) return this.limpiar()
    this.espera = setTimeout(async () => {
      const respuesta = await fetch(`${this.urlValue}?q=${encodeURIComponent(consulta)}`, { headers: { Accept: "application/json" } })
      if (!respuesta.ok || this.textoTarget.value.trim() !== consulta) return
      this.lista = await respuesta.json()
      this.indice = this.lista.length ? 0 : -1
      this.pintar()
    }, 200)
  }

  pintar() {
    this.resultadosTarget.innerHTML = this.lista.length
      ? this.lista.map((p, i) => `<button type="button" class="list-group-item list-group-item-action py-1${i === this.indice ? " active" : ""}"
          data-indice="${i}" data-action="mousedown->buscar-profesor#elegirConRaton">${escapar(p.nombre)} <small>${escapar(p.ci)}</small></button>`).join("")
      : `<div class="list-group-item py-1 text-muted">Ningún profesor coincide</div>`
  }

  tecla(event) {
    if (!this.resultadosTarget.innerHTML) return
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      if (!this.lista.length) return
      this.indice = (this.indice + (event.key === "ArrowDown" ? 1 : -1) + this.lista.length) % this.lista.length
      this.pintar()
    } else if (event.key === "Enter") {
      event.preventDefault()
      this.elegir(this.indice)
    } else if (event.key === "Escape") {
      // Que el Esc cierre la lista y no el panel de la sección.
      event.preventDefault()
      event.stopPropagation()
      this.restaurar()
    }
  }

  // En mousedown, y no en click: así el campo no pierde el foco antes de elegir.
  elegirConRaton(event) {
    event.preventDefault()
    this.elegir(Number(event.currentTarget.dataset.indice))
  }

  elegir(indice) {
    const profesor = this.lista[indice]
    if (!profesor) return
    this.idTarget.value = profesor.id
    this.textoTarget.value = this.elegido = profesor.nombre
    this.limpiar()
  }

  salir() {
    clearTimeout(this.espera)
    this.restaurar()
  }

  restaurar() {
    if (this.textoTarget.value.trim() === "") {
      this.idTarget.value = ""
      this.elegido = ""
    } else {
      this.textoTarget.value = this.elegido
    }
    this.limpiar()
  }

  limpiar() {
    this.resultadosTarget.innerHTML = ""
    this.lista = []
    this.indice = -1
  }
}
