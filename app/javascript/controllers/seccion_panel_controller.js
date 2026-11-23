import { Controller } from "@hotwired/stimulus"

// El panel de una sección en la Programación (FHE 23-nov; nació en FAU el 17-nov): se abre en una fila debajo de la
// asignatura para crear, duplicar o corregir una sección sin salir de la página. Lo que va y viene es Turbo Stream
// (ProgramacionSeccionesController); aquí vive solo lo de la pantalla:
//
//   el código        en mayúsculas y sin espacios, como en el admin, y avisa si ya existe en la asignatura
//   la tabla         su caja tiene 400 px de alto: mientras el panel está abierto se estira, y al cerrarlo
//                    vuelve a su alto con la asignatura a la vista
//   Esc o la ×       cierran sin guardar
//
// FHE no tiene sedes: el código sugerido viene del servidor (Section.siguiente_codigo) y no cambia en la pantalla.
export default class extends Controller {
  static targets = ["tarjeta", "codigo", "avisoCodigo"]
  static values = { existentes: Array }

  connect() {
    this.caja = this.element.closest(".programacion-tabla")
    this.fila = this.element.previousElementSibling
    this.caja?.classList.add("con-panel")
    this.revisarCodigo()
    this.tarjetaTarget.focus({ preventScroll: true })
    // En el cuadro siguiente: al conectarse este controlador, la grilla de adentro todavía no dibujó su lista y la
    // tarjeta es más baja. Sin esperar, el final del panel («Agregar bloque», «Crear sección») quedaba detrás del pie
    // del admin, que es fixed-bottom (23-nov). El hueco del pie lo deja scroll-margin (_programacion_secciones.scss).
    requestAnimationFrame(() => this.tarjetaTarget.scrollIntoView({ block: "nearest", behavior: "instant" }))
  }

  disconnect() {
    // Otro panel tomó su lugar (Duplicar, «Como la», o el motivo de un rechazo): la caja sigue estirada.
    if (!this.caja || this.caja.querySelector(".programacion-panel")) return
    this.caja.classList.remove("con-panel")
    if (this.fila?.isConnected) {
      this.caja.scrollTop += this.fila.getBoundingClientRect().top - this.caja.getBoundingClientRect().top - 48
    }
  }

  cerrar() {
    this.element.remove()
  }

  tecla(event) {
    if (event.key !== "Escape" || event.defaultPrevented || !this.element.isConnected) return
    // La grilla a medio gesto (el primer clic dado, o arrastrando) usa el Esc para cancelar eso.
    if (this.element.querySelector(".hs-guia--activa, .hs-bloque--fantasma")) return
    event.preventDefault()
    this.cerrar()
  }

  escribirCodigo() {
    const limpio = this.codigoTarget.value.toUpperCase().replace(/[^A-Z0-9]/g, "")
    if (limpio !== this.codigoTarget.value) this.codigoTarget.value = limpio
    this.revisarCodigo()
  }

  // Como lo guarda el modelo (Section#set_code_to_02i): «3» queda «03». La unicidad no distingue mayúsculas.
  revisarCodigo() {
    const valor = this.codigoTarget.value
    const codigo = /^\d+$/.test(valor) ? String(Number(valor)).padStart(2, "0") : valor
    const existe = this.existentesValue.some((c) => c.toUpperCase() === codigo)
    this.avisoCodigoTarget.textContent = existe ? ` La ${codigo} ya existe.` : ""
    this.codigoTarget.classList.toggle("is-invalid", existe)
  }
}
