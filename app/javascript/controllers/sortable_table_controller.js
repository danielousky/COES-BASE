import { Controller } from "@hotwired/stimulus"

// Client-side sort para tablas con datasets acotados.
// Uso:
//   %table{data: { controller: 'sortable-table', 'sortable-table-default-key-value': 'code' }}
//     %thead
//       %tr
//         %th{data: { action: 'click->sortable-table#sort', 'sort-key': 'code' }}
//           Asignatura
//           %span{data: { 'sort-arrow': 'code' }}
//     %tbody{data: { 'sortable-table-target': 'body' }}
//       %tr
//         %td{data: { 'sort-value-code': subject.code }}= subject.code
export default class extends Controller {
  static targets = ["body"]
  static values = {
    defaultKey: String,
    defaultDir: { type: String, default: "asc" }
  }

  connect() {
    if (this.defaultKeyValue) {
      this.applySort(this.defaultKeyValue, this.defaultDirValue)
    }
  }

  sort(event) {
    const th = event.currentTarget
    const key = th.dataset.sortKey
    if (!key) return
    const current = this.element.dataset.currentSort
    const currentDir = this.element.dataset.currentDir || "asc"
    const nextDir = (current === key && currentDir === "asc") ? "desc" : "asc"
    this.applySort(key, nextDir)
  }

  applySort(key, direction) {
    const datasetAttr = `sortValue${key.charAt(0).toUpperCase()}${key.slice(1)}`
    const rows = Array.from(this.bodyTarget.querySelectorAll("tr"))
    rows.sort((a, b) => {
      const cellA = a.querySelector(`[data-sort-value-${key}]`)
      const cellB = b.querySelector(`[data-sort-value-${key}]`)
      const va = (cellA && cellA.dataset[datasetAttr]) || ""
      const vb = (cellB && cellB.dataset[datasetAttr]) || ""
      const cmp = va.localeCompare(vb, undefined, { numeric: true, sensitivity: "base" })
      return direction === "asc" ? cmp : -cmp
    })
    rows.forEach(r => this.bodyTarget.appendChild(r))

    this.element.dataset.currentSort = key
    this.element.dataset.currentDir = direction

    this.element.querySelectorAll("[data-sort-arrow]").forEach(span => {
      const k = span.dataset.sortArrow
      span.textContent = (k === key) ? (direction === "asc" ? " ▲" : " ▼") : ""
    })
  }
}
