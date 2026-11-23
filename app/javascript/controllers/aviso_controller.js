import { Controller } from "@hotwired/stimulus"

// Un aviso de toastr que llega por Turbo Stream (la Programación, 17-nov): se muestra al conectarse y el
// elemento se va. Así una respuesta del servidor avisa sin recargar la página.
//   <div data-controller="aviso" data-aviso-tipo-value="success" data-aviso-texto-value="Se eliminó la sección 02.">
export default class extends Controller {
  static values = { tipo: String, texto: String }

  connect() {
    window.toastr?.[this.tipoValue || "info"]?.(this.textoValue)
    this.element.remove()
  }
}
