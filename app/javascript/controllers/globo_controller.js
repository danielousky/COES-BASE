import { Controller } from "@hotwired/stimulus"
import { Tooltip } from "bootstrap"

// El globo de Bootstrap de un elemento que llega después de cargar la página (23-nov): las secciones de la
// Programación y su panel, que vienen por Turbo Stream, y los bordes, la × y la papelera de la grilla semanal, que se
// redibujan a cada cambio. ui.js prepara los [data-bs-toggle="tooltip"] solo al cargar la página: sin este
// controlador, lo que llega después mostraba el globo del navegador. Lo crea al conectarse y lo quita al irse, para
// que no quede uno colgado en pantalla.
//   <a title="Lu 07AM 08:30AM | Pérez, Ana" data-controller="globo">
//
// Va arriba (o abajo, si arriba no cabe), nunca a un lado: junto al borde de la tabla, Bootstrap mandaba a la
// izquierda el globo del + y de la papelera, encima de las secciones, y el clic en una sección le caía al globo.
// Por lo mismo, el globo no recibe el ratón (components/_globo.scss).
// Bootstrap se importa aquí y no se toma de window: en el admin, el global lo pone ui.js.
export default class extends Controller {
  connect() {
    const lugares = this.element.dataset.bsPlacement === "bottom" ? ["bottom", "top"] : ["top", "bottom"]
    this.globo = Tooltip.getOrCreateInstance(this.element, { fallbackPlacements: lugares, customClass: "globo" })
  }

  // Si estaba a la vista, se desvanece, y se desecha después. Desecharlo a medio desvanecer (.fade dura 150 ms) da un
  // error en Bootstrap 5.2 («Cannot convert undefined or null to object»): le pasaba a la × de un bloque cuando se
  // escribía el aula justo después de quitarle el ratón, porque la grilla se redibuja.
  disconnect() {
    const globo = this.globo
    globo.hide()
    setTimeout(() => globo.dispose(), 300)
  }
}
