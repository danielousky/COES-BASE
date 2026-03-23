import ApexCharts from 'apexcharts';

// Almacenar instancias de charts e intervals para limpiarlas en re-navegación
var chartInstances = [];
var activeIntervals = [];
var dashboardInitialized = false;

function cleanup() {
  chartInstances.forEach(function (chart) {
    try { chart.destroy(); } catch (e) { /* ignorar */ }
  });
  chartInstances = [];

  activeIntervals.forEach(function (id) {
    clearInterval(id);
  });
  activeIntervals = [];

  dashboardInitialized = false;
}

function sanitizeNumbers(arr) {
  return (arr || []).map(function(v) { return (typeof v === 'number' && !isNaN(v)) ? v : 0; });
}

function createChart(el, options) {
  var chart = new ApexCharts(el, options);
  chartInstances.push(chart);
  chart.render();
  return chart;
}

function initDashboard() {
  // Solo ejecutar si estamos en la página del dashboard
  if (!document.querySelector('#chart-enrollment') && !document.querySelector('#chart-approval')) return;

  if (dashboardInitialized) return;
  dashboardInitialized = true;

  // Cada init aislado para que un error no bloquee los demás
  var inits = [
    initCountUpAnimations,
    initApprovalGauge,
    initEnrollmentChart,
    initQualificationsChart,
    initSparklines,
    initAutoRefresh
  ];
  inits.forEach(function (fn) {
    try { fn(); } catch (e) { console.warn('[Dashboard] Error en ' + fn.name + ':', e); }
  });
}

// Limpiar al salir de la página (Turbo)
document.addEventListener("turbo:before-render", cleanup);

document.addEventListener("rails_admin.dom_ready", initDashboard);
document.addEventListener("turbo:load", initDashboard);

// ── Animación de contador reutilizable ───────────────────────────────
function animateCounter(el, target, duration) {
  duration = duration || 1500;
  var start = parseInt(el.textContent.replace(/\./g, '')) || 0;
  var startTime = performance.now();

  function update(currentTime) {
    var elapsed = currentTime - startTime;
    var progress = Math.min(elapsed / duration, 1);
    var eased = 1 - Math.pow(1 - progress, 3);
    el.textContent = Math.round(start + (target - start) * eased).toLocaleString('es-VE');
    if (progress < 1) requestAnimationFrame(update);
  }
  requestAnimationFrame(update);
}

// ── Contadores animados (count-up) ──────────────────────────────────
function initCountUpAnimations() {
  document.querySelectorAll('.countup').forEach(function (el) {
    var target = parseInt(el.dataset.target) || 0;
    if (target === 0) return;
    el.textContent = '0';
    animateCounter(el, target);
  });
}

// ── Radial Gauge: Tasa de Aprobación ────────────────────────────────
function initApprovalGauge() {
  var el = document.querySelector('#chart-approval');
  if (!el) return;

  var rate = parseInt(el.dataset.rate);
  if (isNaN(rate)) return;

  var color = '#198754'; // success
  if (rate < 50) color = '#dc3545'; // danger
  else if (rate < 70) color = '#ffc107'; // warning

  createChart(el, {
    chart: { type: 'radialBar', height: 160, sparkline: { enabled: true } },
    plotOptions: {
      radialBar: {
        startAngle: -135,
        endAngle: 135,
        hollow: { size: '60%' },
        track: { background: '#e9ecef', strokeWidth: '100%' },
        dataLabels: {
          name: { show: true, offsetY: -10, fontSize: '11px', color: '#6c757d' },
          value: {
            fontSize: '28px', fontWeight: 700, color: color,
            formatter: function (val) { return val + '%'; }
          }
        }
      }
    },
    fill: { colors: [color] },
    series: [rate],
    labels: ['Aprobación']
  });
}

// ── Bar Chart: Inscripciones por Escuela ────────────────────────────
function initEnrollmentChart() {
  var el = document.querySelector('#chart-enrollment');
  if (!el || !el.dataset.chart) return;

  var data;
  try { data = JSON.parse(el.dataset.chart); } catch (e) { return; }
  if (!data || !data.labels || !data.labels.length) return;

  createChart(el, {
    chart: {
      type: 'bar', height: 280, stacked: true,
      toolbar: { show: false },
      animations: { enabled: true, speed: 800, animateGradually: { enabled: true, delay: 150 } }
    },
    plotOptions: { bar: { horizontal: true, barHeight: '55%', borderRadius: 3 } },
    colors: ['#198754', '#0d6efd', '#ffc107'],
    series: [
      { name: 'Confirmados', data: sanitizeNumbers(data.confirmado) },
      { name: 'Preinscritos', data: sanitizeNumbers(data.preinscrito) },
      { name: 'Reservados', data: sanitizeNumbers(data.reservado) }
    ],
    xaxis: { categories: data.labels },
    yaxis: { labels: { style: { fontSize: '12px', fontWeight: 600 } } },
    legend: { position: 'top', horizontalAlign: 'left', fontSize: '12px' },
    dataLabels: { enabled: false },
    grid: { borderColor: '#f1f1f1' },
    tooltip: { y: { formatter: function (val) { return val + ' estudiantes'; } } }
  });
}

// ── Donut Chart: Estado de Calificaciones ───────────────────────────
function initQualificationsChart() {
  var el = document.querySelector('#chart-qualifications');
  if (!el || !el.dataset.chart) return;

  var data;
  try { data = JSON.parse(el.dataset.chart); } catch (e) { return; }
  if (!data || !data.labels || !data.values) return;

  var values = sanitizeNumbers(data.values);

  createChart(el, {
    chart: {
      type: 'donut', height: 280,
      animations: { enabled: true, speed: 800, animateGradually: { enabled: true, delay: 200 } }
    },
    labels: data.labels,
    series: values,
    colors: ['#198754', '#dc3545', '#6c757d', '#adb5bd', '#842029'],
    plotOptions: {
      pie: {
        donut: {
          size: '55%',
          labels: {
            show: true,
            total: {
              show: true, label: 'Total',
              formatter: function (w) {
                return w.globals.seriesTotals.reduce(function (a, b) { return a + b; }, 0).toLocaleString('es-VE');
              }
            }
          }
        }
      }
    },
    legend: { position: 'bottom', fontSize: '12px' },
    dataLabels: { enabled: true, formatter: function (val) { return val.toFixed(0) + '%'; } }
  });
}

// ── Sparklines: Tendencia de inscripción ────────────────────────────
function initSparklines() {
  var el = document.querySelector('#spark-enrollment');
  if (!el || !el.dataset.values) return;

  var values;
  try { values = JSON.parse(el.dataset.values); } catch (e) { return; }
  if (!values || values.length < 2) return;

  values = sanitizeNumbers(values);

  createChart(el, {
    chart: { type: 'area', height: 35, sparkline: { enabled: true } },
    stroke: { width: 2, curve: 'smooth' },
    fill: { type: 'gradient', gradient: { opacityFrom: 0.4, opacityTo: 0.05 } },
    series: [{ data: values }],
    colors: ['#0d6efd'],
    tooltip: { enabled: false }
  });
}

// ── Auto-refresh: Polling de inscripción (cada 30s) ─────────────────
function initAutoRefresh() {
  var indicator = document.querySelector('#live-indicator');
  if (!indicator) return;

  var lastUpdated = document.querySelector('#last-updated');
  var secondsAgo = 0;

  // Actualizar texto "hace Xs"
  activeIntervals.push(setInterval(function () {
    secondsAgo++;
    if (lastUpdated) {
      if (secondsAgo < 60) {
        lastUpdated.textContent = 'Hace ' + secondsAgo + 's';
      } else {
        lastUpdated.textContent = 'Hace ' + Math.floor(secondsAgo / 60) + 'min';
      }
    }
  }, 1000));

  // Fetch datos cada 30 segundos
  activeIntervals.push(setInterval(function () {
    fetch('/admin_dashboard/enrollment_counts')
      .then(function (r) {
        if (r.status === 401 || r.status === 403) {
          cleanup();
          return null;
        }
        return r.json();
      })
      .then(function (data) {
        if (!data) return;
        if (data.totals) {
          secondsAgo = 0;
          // Animar los contadores del card de inscritos
          var card = document.querySelector('.border-primary .card-body');
          if (card) {
            var countups = card.querySelectorAll('.countup');
            var values = [data.totals.total, data.totals.confirmado, data.totals.preinscrito, data.totals.reservado];
            countups.forEach(function (el, i) {
              if (i < values.length && parseInt(el.textContent.replace(/\./g, '')) !== values[i]) {
                el.dataset.target = values[i];
                animateCounter(el, values[i], 800);
              }
            });
          }
        }
        // Actualizar panel de admins activos
        if (data.active_admins) {
          updateActiveAdminsPanel(data.active_admins);
        }
      })
      .catch(function () { /* silenciar errores de red */ });
  }, 30000));
}

// ── Escape HTML para prevenir XSS ───────────────────────────────────
function escapeHtml(str) {
  var div = document.createElement('div');
  div.appendChild(document.createTextNode(str || ''));
  return div.innerHTML;
}

// ── Actualizar panel de admins activos ───────────────────────────────
function updateActiveAdminsPanel(admins) {
  var panel = document.querySelector('#active-admins-panel');
  if (!panel) return;

  var badge = panel.querySelector('.badge.bg-secondary');
  if (badge) badge.textContent = admins.length;

  var list = panel.querySelector('.list-group');
  if (!list || admins.length === 0) return;

  var colors = ['#0d6efd', '#198754', '#dc3545', '#ffc107', '#0dcaf0', '#6f42c1', '#fd7e14', '#20c997'];

  var html = admins.map(function (admin) {
    var dotClass = admin.active
      ? '<span class="position-absolute live-pulse-sm" style="bottom: 0; right: 0;"></span>'
      : '<span class="position-absolute rounded-circle bg-secondary" style="bottom: 0; right: 0; width: 8px; height: 8px; border: 1px solid white;"></span>';

    var avatar = '<div class="d-flex align-items-center justify-content-center rounded-circle text-white fw-bold" style="width: 32px; height: 32px; font-size: 0.7rem; background: ' + colors[Math.abs(admin.name.length) % colors.length] + ';">' + escapeHtml(admin.initials) + '</div>';

    var actionText = admin.last_action
      ? '<small class="text-muted text-truncate d-block" style="font-size: 0.72rem">' + escapeHtml(admin.last_action) + (admin.last_action_ago ? ' · ' + escapeHtml(admin.last_action_ago) : '') + '</small>'
      : '';

    return '<div class="list-group-item px-3 py-2"><div class="d-flex align-items-center gap-2"><div class="position-relative">' + avatar + dotClass + '</div><div class="flex-grow-1" style="min-width: 0"><div class="d-flex justify-content-between align-items-center"><span class="fw-semibold" style="font-size: 0.85rem">' + escapeHtml(admin.name) + '</span><span class="badge bg-opacity-10 bg-secondary text-secondary" style="font-size: 0.65rem">' + escapeHtml(admin.role) + '</span></div>' + actionText + '</div></div></div>';
  }).join('');

  list.innerHTML = html;
}
