import { Controller } from "@hotwired/stimulus"

// Guarda un único campo al cambiarlo, con un PATCH en JSON: en su sitio, sin botón.
// Sirve para cualquier modelo; con una casilla manda true/false y, si el servidor
// no lo acepta, la casilla vuelve a como estaba.
// Es común a COES FHE y FAU: el archivo es el mismo en los dos repos.
//
// Uso esperado:
//   %input{data: { controller: "field-update",
//                  "field-update-url-value": main_app.course_path(course),
//                  "field-update-model-value": "course",
//                  "field-update-field-value": "offer",
//                  action: "change->field-update#patch" }}
//
// El servidor responde { data: "mensaje", type: "success" | "danger" }.
export default class extends Controller {
  static values = { url: String, model: String, field: String }

  async patch(event) {
    const input = event.target
    const casilla = input.type === "checkbox"
    const value = casilla ? input.checked : (input.value === "" ? null : input.value)
    input.disabled = true

    try {
      const resp = await fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": this.csrfToken
        },
        body: JSON.stringify({ [this.modelValue]: { [this.fieldValue]: value } })
      })
      const json = await resp.json()
      input.disabled = false

      if (json.type === "danger") {
        if (casilla) input.checked = !value
        this.notify("error", json.data)
        return
      }

      this.notify("success", json.data)
    } catch (err) {
      input.disabled = false
      if (casilla) input.checked = !value
      this.notify("error", "No se pudo actualizar. Inténtelo nuevamente.")
    }
  }

  // Enter en un input dentro de un <form> lo envía por defecto: en FAU, el ordinal vive dentro
  // del edit del plan (StudyPlan#edit) y mandaría el formulario completo. blur() alcanza:
  // dispara el cambio (evento "change") sin dejar que el Enter siga su curso hacia el form.
  preventSubmit(event) {
    event.preventDefault()
    event.target.blur()
  }

  notify(type, msg) {
    if (window.toastr) window.toastr[type](msg)
    else window.alert(msg)
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.getAttribute("content")
  }
}
