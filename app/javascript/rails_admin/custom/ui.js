//= require_tree .

import * as toastr from "toastr";
window.toastr = toastr;

import * as bootstrap from 'bootstrap';
window.bootstrap = bootstrap;
// import "trix"
import "@rails/actiontext"

// Almacenar instancias de tooltips para limpiarlas en re-navegación
var activeTooltips = [];

function disposeTooltips() {
  activeTooltips.forEach(function(tt) {
    try { tt.dispose(); } catch(e) { /* ignorar */ }
  });
  activeTooltips = [];
}

function initTooltips() {
  // Limpiar tooltips anteriores antes de re-inicializar
  disposeTooltips();

  // Inicializar SOLO en elementos con data-bs-toggle="tooltip" (una sola vez)
  var triggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'));
  activeTooltips = triggerList.map(function(el) {
    // Verificar que no tenga ya una instancia
    var existing = bootstrap.Tooltip.getInstance(el);
    if (existing) return existing;
    return new bootstrap.Tooltip(el);
  });
}

document.addEventListener("rails_admin.dom_ready", function() {
  $('#update_if_exists').removeClass('form-control');
  $(".form-text:not(:has(span))").addClass('alert alert-warning');

  initTooltips();
});

// Cerrar modales Bootstrap y limpiar tooltips antes de que Turbo reemplace el DOM.
// Sin esto, Turbo navega con body.modal-open y backdrop activo, causando
// un estado residual que bloquea la interacción con la página.
function dismissModalsAndTooltips() {
  // Cerrar todos los modales abiertos (con y sin .fade)
  document.querySelectorAll('.modal.show').forEach(function(el) {
    var instance = bootstrap.Modal.getInstance(el);
    if (instance) {
      try { instance.hide(); } catch(e) { /* ignorar */ }
      try { instance.dispose(); } catch(e) { /* ignorar */ }
    }
    // Limpiar estado del DOM directamente por si Bootstrap no alcanzó
    el.classList.remove('show');
    el.removeAttribute('style');
    el.setAttribute('aria-hidden', 'true');
  });
  // Fallback: limpiar estado residual global
  document.body.classList.remove('modal-open');
  document.body.style.removeProperty('overflow');
  document.body.style.removeProperty('padding-right');
  document.querySelectorAll('.modal-backdrop').forEach(function(el) { el.remove(); });

  disposeTooltips();
}

document.addEventListener("turbo:before-render", dismissModalsAndTooltips);
