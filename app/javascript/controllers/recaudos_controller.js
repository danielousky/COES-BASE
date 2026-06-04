import { Controller } from "@hotwired/stimulus"
import { Modal, Tooltip } from "bootstrap"

// Lazy-load del modal de Recaudos por Grade — evita pre-renderizar N modales
// por página y sus queries asociadas.
export default class extends Controller {
  static targets = ["modal", "content"]
  static values  = { url: String }

  connect() {
    this.bsModal = new Modal(this.modalTarget)
    this.skeleton = this.contentTarget.innerHTML
  }

  async open({ params }) {
    this.contentTarget.innerHTML = this.skeleton
    this.bsModal.show()

    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("recaudos_for", params.gradeId)
    url.searchParams.set("current_tab", params.tab || "")

    try {
      const resp = await fetch(url, { headers: { "Accept": "text/html", "X-Requested-With": "XMLHttpRequest" } })
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`)
      this.contentTarget.innerHTML = await resp.text()
      this.contentTarget.querySelectorAll('[data-bs-toggle="tooltip"]').forEach(el => new Tooltip(el))
    } catch (err) {
      this.contentTarget.innerHTML = `<div class="modal-body alert alert-danger m-3">No se pudo cargar el detalle: ${err.message}</div>`
    }
  }
}
