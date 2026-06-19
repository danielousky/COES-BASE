import { Controller } from "@hotwired/stimulus"

// Inscripción de asignaturas (preinscripción del estudiante).
// Reemplaza el JS inline previo (jQuery + toastr + handlers onchange/onclick):
//   - reserve: reserva/libera el cupo de una sección vía AJAX (reserve_space).
//   - totalize: recalcula créditos/asignaturas y habilita el botón Completar.
//   - filter: filtra la oferta por código/nombre de asignatura.
//   - confirm: confirma la preinscripción (definitiva).
//
// Notifica con window.toastr (global, cargado en application.js y rails_admin.js).
export default class extends Controller {
  static targets = ["select", "creditsCount", "subjectsCount", "creditsField", "subjectsField", "submit"]
  static values = {
    reserveUrl:   String,
    creditLimit:  Number,
    subjectLimit: Number,
    processName:  String,
    schoolName:   String
  }

  // Reserva (o libera, si value vacío) el cupo de la sección elegida.
  reserve(event) {
    const select = event.target
    const option = select.options[select.selectedIndex]
    const params = new URLSearchParams({
      section_id:          select.value,
      course_id:           select.dataset.courseId,
      grade_id:            select.dataset.gradeId,
      academic_process_id: select.dataset.academicProcessId,
      pci:                 select.dataset.pci
    })

    fetch(`${this.reserveUrlValue}?${params}`, {
      method:  "POST",
      headers: { "X-CSRF-Token": this.csrfToken, "Accept": "application/json" }
    })
      .then(resp => resp.json())
      .then(data => {
        if (data.status === "success") {
          this.notify("success", data.data)
          const row = select.closest("tr")
          if (row) row.classList.toggle("table-success", select.value !== "")
          this.totalize()
        } else {
          this.notify("error", data.data)
          select.selectedIndex = 0
        }
        if (option) option.text = data.cupo
        // Refrescar el conteo de la sección cuyo cupo se devolvió (al liberar o
        // al cambiar de sección): su opción sigue en el select, sin estar seleccionada.
        if (data.liberada_id) {
          const liberada = select.querySelector(`option[value="${data.liberada_id}"]`)
          if (liberada) liberada.text = data.liberada_cupo
        }
      })
      .catch(() => this.notify("error", "No se pudo completar la operación. Por favor, intente nuevamente."))
  }

  // Recalcula totales seleccionados y habilita/inhabilita Completar.
  totalize() {
    let credits = 0
    let subjects = 0
    this.selectTargets.forEach(select => {
      if (select.value !== "") {
        subjects += 1
        credits += Number(select.dataset.credits)
      }
    })

    this.creditsCountTarget.textContent = credits
    this.subjectsCountTarget.textContent = subjects
    this.creditsFieldTarget.value = credits
    this.subjectsFieldTarget.value = subjects

    const active = subjects > 0 && subjects <= this.subjectLimitValue && credits <= this.creditLimitValue
    this.submitTarget.classList.toggle("disabled", !active)
    this.submitTarget.disabled = !active

    ;[this.creditsCountTarget.closest("tr"), this.subjectsCountTarget.closest("tr")].forEach(row => {
      if (!row) return
      row.classList.toggle("table-success", active)
      row.classList.toggle("table-danger", !active)
    })
  }

  // Filtra las filas de la tabla de oferta (la que contiene el input) por keyword.
  filter(event) {
    const keyword = event.target.value.toUpperCase()
    const table = event.target.closest("table")
    if (!table) return
    table.querySelectorAll("tbody tr").forEach(row => {
      const nameCell = row.getElementsByTagName("td")[1]
      if (!nameCell) return
      const value = (nameCell.textContent || nameCell.innerText).toUpperCase()
      row.style.display = value.indexOf(keyword) > -1 ? "" : "none"
    })
  }

  // Confirma la preinscripción: exige al menos una asignatura y advierte que es definitiva.
  confirm(event) {
    const titles = this.selectTargets
      .filter(select => select.value !== "")
      .map(select => select.dataset.titulo)

    if (titles.length === 0) {
      event.preventDefault()
      window.alert("ATENCIÓN: DEBE SELECCIONAR AL MENOS UNA ASIGNATURA A INSCRIBIR")
      return
    }

    let msg = `${titles.length} Asignaturas a preinscribir en el período académico ${this.processNameValue} de ${this.schoolNameValue}:\n\n`
    msg += titles.join("\n")
    msg += "\n\nRECUERDE QUE SU ELECCIÓN ES DEFINITIVA Y NO PODRÁ SER CAMBIADA. ¿Está seguro?"

    if (!window.confirm(msg)) event.preventDefault()
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }

  notify(type, message) {
    if (!message) return
    if (window.toastr && typeof window.toastr[type] === "function") window.toastr[type](message)
  }
}
