// JavaScript para mejorar la interactividad de las bitácoras

document.addEventListener('DOMContentLoaded', function() {
  // Inicializar tooltips de Bootstrap
  var tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'));
  var tooltipList = tooltipTriggerList.map(function (tooltipTriggerEl) {
    return new bootstrap.Tooltip(tooltipTriggerEl);
  });

  // Inicializar filtros en tiempo real
  initializeRealTimeFilters();
  
  // Inicializar timeline interactivo
  initializeTimeline();
  
  // Inicializar gráficos de estadísticas
  initializeCharts();
  
  // Inicializar exportación
  initializeExport();
});

function initializeRealTimeFilters() {
  const filterForm = document.querySelector('#audit-filter-form');
  if (!filterForm) return;

  const filterInputs = filterForm.querySelectorAll('select, input');
  
  filterInputs.forEach(input => {
    input.addEventListener('change', function() {
      // Agregar indicador de carga
      const submitBtn = filterForm.querySelector('input[type="submit"]');
      if (submitBtn) {
        submitBtn.innerHTML = '<i class="fa fa-spinner fa-spin me-1"></i>Filtrando...';
        submitBtn.disabled = true;
      }
      
      // Enviar formulario automáticamente
      setTimeout(() => {
        filterForm.submit();
      }, 300);
    });
  });
}

function initializeTimeline() {
  const timelineItems = document.querySelectorAll('.timeline-item');
  
  timelineItems.forEach((item, index) => {
    // Agregar animación de entrada
    item.style.opacity = '0';
    item.style.transform = 'translateX(-20px)';
    
    setTimeout(() => {
      item.style.transition = 'all 0.5s ease';
      item.style.opacity = '1';
      item.style.transform = 'translateX(0)';
    }, index * 100);
    
    // Agregar efecto hover
    item.addEventListener('mouseenter', function() {
      this.style.transform = 'translateX(5px)';
      this.style.boxShadow = '0 4px 8px rgba(0,0,0,0.15)';
    });
    
    item.addEventListener('mouseleave', function() {
      this.style.transform = 'translateX(0)';
      this.style.boxShadow = '0 2px 4px rgba(0,0,0,0.1)';
    });
  });
}

function initializeCharts() {
  // Gráfico de actividad por tipo
  const activityChart = document.getElementById('activity-chart');
  if (activityChart) {
    const ctx = activityChart.getContext('2d');
    const data = JSON.parse(activityChart.dataset.chartData || '{}');
    
    new Chart(ctx, {
      type: 'doughnut',
      data: {
        labels: Object.keys(data),
        datasets: [{
          data: Object.values(data),
          backgroundColor: [
            '#007bff',
            '#28a745',
            '#ffc107',
            '#dc3545',
            '#6c757d',
            '#17a2b8',
            '#6f42c1',
            '#e83e8c'
          ],
          borderWidth: 2,
          borderColor: '#fff'
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            position: 'bottom',
            labels: {
              padding: 20,
              usePointStyle: true
            }
          }
        }
      }
    });
  }
  
  // Gráfico de actividad temporal
  const timelineChart = document.getElementById('timeline-chart');
  if (timelineChart) {
    const ctx = timelineChart.getContext('2d');
    const data = JSON.parse(timelineChart.dataset.chartData || '{}');
    
    new Chart(ctx, {
      type: 'line',
      data: {
        labels: Object.keys(data),
        datasets: [{
          label: 'Eventos',
          data: Object.values(data),
          borderColor: '#007bff',
          backgroundColor: 'rgba(0, 123, 255, 0.1)',
          borderWidth: 2,
          fill: true,
          tension: 0.4
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          y: {
            beginAtZero: true,
            ticks: {
              stepSize: 1
            }
          }
        },
        plugins: {
          legend: {
            display: false
          }
        }
      }
    });
  }
}

function initializeExport() {
  const exportButtons = document.querySelectorAll('.export-btn');
  
  exportButtons.forEach(button => {
    button.addEventListener('click', function(e) {
      e.preventDefault();
      
      const format = this.dataset.format;
      const url = this.href;
      
      // Mostrar modal de confirmación
      showExportModal(format, url);
    });
  });
}

function showExportModal(format, url) {
  const modal = document.createElement('div');
  modal.className = 'modal fade';
  modal.innerHTML = `
    <div class="modal-dialog">
      <div class="modal-content">
        <div class="modal-header">
          <h5 class="modal-title">Exportar Bitácoras</h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
        </div>
        <div class="modal-body">
          <p>¿Está seguro que desea exportar las bitácoras en formato ${format.toUpperCase()}?</p>
          <div class="alert alert-info">
            <i class="fa fa-info-circle me-1"></i>
            El archivo se descargará automáticamente una vez procesado.
          </div>
        </div>
        <div class="modal-footer">
          <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Cancelar</button>
          <button type="button" class="btn btn-primary" id="confirm-export">
            <i class="fa fa-download me-1"></i>Exportar
          </button>
        </div>
      </div>
    </div>
  `;
  
  document.body.appendChild(modal);
  
  const bootstrapModal = new bootstrap.Modal(modal);
  bootstrapModal.show();
  
  document.getElementById('confirm-export').addEventListener('click', function() {
    this.innerHTML = '<i class="fa fa-spinner fa-spin me-1"></i>Exportando...';
    this.disabled = true;
    
    // Redirigir a la URL de exportación
    window.location.href = url;
    
    // Cerrar modal después de un breve delay
    setTimeout(() => {
      bootstrapModal.hide();
      document.body.removeChild(modal);
    }, 1000);
  });
  
  // Limpiar modal cuando se cierre
  modal.addEventListener('hidden.bs.modal', function() {
    document.body.removeChild(modal);
  });
}

// Función para refrescar estadísticas en tiempo real
function refreshStats() {
  const statsContainer = document.querySelector('.audit-stats');
  if (!statsContainer) return;
  
  fetch('/audit_trails/stats.json')
    .then(response => response.json())
    .then(data => {
      updateStatsDisplay(data);
    })
    .catch(error => {
      console.error('Error al actualizar estadísticas:', error);
    });
}

function updateStatsDisplay(stats) {
  const statElements = {
    'total-events': stats.total_events,
    'user-registrations': stats.user_registrations,
    'academic-events': stats.academic_events,
    'events-today': stats.events_today
  };
  
  Object.entries(statElements).forEach(([id, value]) => {
    const element = document.getElementById(id);
    if (element) {
      animateNumber(element, parseInt(element.textContent) || 0, value);
    }
  });
}

function animateNumber(element, start, end) {
  const duration = 1000;
  const startTime = performance.now();
  
  function updateNumber(currentTime) {
    const elapsed = currentTime - startTime;
    const progress = Math.min(elapsed / duration, 1);
    
    const current = Math.floor(start + (end - start) * progress);
    element.textContent = current.toLocaleString();
    
    if (progress < 1) {
      requestAnimationFrame(updateNumber);
    }
  }
  
  requestAnimationFrame(updateNumber);
}

// Función para buscar en tiempo real
function initializeSearch() {
  const searchInput = document.querySelector('#audit-search');
  if (!searchInput) return;
  
  let searchTimeout;
  
  searchInput.addEventListener('input', function() {
    clearTimeout(searchTimeout);
    
    searchTimeout = setTimeout(() => {
      const query = this.value.trim();
      if (query.length >= 2) {
        performSearch(query);
      } else if (query.length === 0) {
        clearSearch();
      }
    }, 300);
  });
}

function performSearch(query) {
  const rows = document.querySelectorAll('.audit-table tbody tr');
  
  rows.forEach(row => {
    const text = row.textContent.toLowerCase();
    if (text.includes(query.toLowerCase())) {
      row.style.display = '';
      row.classList.add('search-highlight');
    } else {
      row.style.display = 'none';
      row.classList.remove('search-highlight');
    }
  });
  
  // Mostrar mensaje si no hay resultados
  const visibleRows = document.querySelectorAll('.audit-table tbody tr[style=""]');
  const noResultsMsg = document.querySelector('.no-results-message');
  
  if (visibleRows.length === 0 && !noResultsMsg) {
    const tbody = document.querySelector('.audit-table tbody');
    const message = document.createElement('tr');
    message.className = 'no-results-message';
    message.innerHTML = `
      <td colspan="6" class="text-center text-muted py-4">
        <i class="fa fa-search fa-2x mb-2"></i><br>
        No se encontraron resultados para "${query}"
      </td>
    `;
    tbody.appendChild(message);
  } else if (visibleRows.length > 0 && noResultsMsg) {
    noResultsMsg.remove();
  }
}

function clearSearch() {
  const rows = document.querySelectorAll('.audit-table tbody tr');
  rows.forEach(row => {
    row.style.display = '';
    row.classList.remove('search-highlight');
  });
  
  const noResultsMsg = document.querySelector('.no-results-message');
  if (noResultsMsg) {
    noResultsMsg.remove();
  }
}

// Función para copiar información de bitácora
function copyAuditInfo(auditId) {
  const auditRow = document.querySelector(`tr[data-audit-id="${auditId}"]`);
  if (!auditRow) return;
  
  const info = {
    fecha: auditRow.querySelector('.audit-date').textContent,
    evento: auditRow.querySelector('.audit-event').textContent,
    tipo: auditRow.querySelector('.audit-type').textContent,
    usuario: auditRow.querySelector('.audit-user').textContent
  };
  
  const text = `Bitácora: ${info.fecha} - ${info.evento} de ${info.tipo} por ${info.usuario}`;
  
  navigator.clipboard.writeText(text).then(() => {
    showToast('Información copiada al portapapeles', 'success');
  }).catch(() => {
    showToast('Error al copiar información', 'error');
  });
}

function showToast(message, type = 'info') {
  const toast = document.createElement('div');
  toast.className = `toast align-items-center text-white bg-${type === 'success' ? 'success' : 'danger'} border-0`;
  toast.setAttribute('role', 'alert');
  toast.innerHTML = `
    <div class="d-flex">
      <div class="toast-body">${message}</div>
      <button type="button" class="btn-close btn-close-white me-2 m-auto" data-bs-dismiss="toast"></button>
    </div>
  `;
  
  const toastContainer = document.querySelector('.toast-container') || createToastContainer();
  toastContainer.appendChild(toast);
  
  const bootstrapToast = new bootstrap.Toast(toast);
  bootstrapToast.show();
  
  toast.addEventListener('hidden.bs.toast', function() {
    toastContainer.removeChild(toast);
  });
}

function createToastContainer() {
  const container = document.createElement('div');
  container.className = 'toast-container position-fixed top-0 end-0 p-3';
  container.style.zIndex = '9999';
  document.body.appendChild(container);
  return container;
}

