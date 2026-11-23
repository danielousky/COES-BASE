import { Controller } from "@hotwired/stimulus"

// El globo de Bootstrap de un elemento que puede llegar por Turbo Stream (las secciones de la Programación,
// 23-nov). ui.js prepara los [data-bs-toggle="tooltip"] solo al cargar la página, así que lo que llega después se
// quedaba sin globo. Este lo crea al conectarse y lo quita al irse, para que no quede uno colgado en pantalla.
//   <a title="Lu 07AM 08:30AM | Pérez, Ana" data-controller="globo">
export default class extends Controller {
  connect() {
    this.globo = window.bootstrap?.Tooltip.getOrCreateInstance(this.element)
  }

  disconnect() {
    this.globo?.dispose()
  }
}
