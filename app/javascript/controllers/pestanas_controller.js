import { Controller } from "@hotwired/stimulus"

// Pestañas que cambian sin ir al servidor: todos los paneles ya están en la página.
// La elegida viaja en el parámetro `vista` de la URL y de los enlaces marcados como `enlace`
// (los períodos del Premio al Mérito), para que al cambiar de período o recargar siga en la misma.
export default class extends Controller {
  static targets = ["boton", "panel", "enlace"]

  mostrar(event) {
    const clave = event.currentTarget.dataset.clave
    this.botonTargets.forEach((boton) => boton.classList.toggle("active", boton.dataset.clave === clave))
    this.panelTargets.forEach((panel) => { panel.hidden = panel.dataset.clave !== clave })
    this.enlaceTargets.forEach((enlace) => { enlace.href = this.conVista(enlace.href, clave) })
    // Conserva el estado de Turbo en el historial: solo cambia la dirección.
    history.replaceState(history.state, "", this.conVista(location.href, clave))
  }

  conVista(direccion, clave) {
    const url = new URL(direccion, location.href)
    url.searchParams.set("vista", clave)
    return url.toString()
  }
}
