import ApexCharts from 'apexcharts';

// Almacenar instancias de charts para destruirlas en re-navegación
var chartInstances = [];

function destroyCharts() {
  chartInstances.forEach(function (chart) {
    try { chart.destroy(); } catch (e) { /* ignorar */ }
  });
  chartInstances = [];
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

  // Destruir charts anteriores (re-navegación turbo/pjax)
  destroyCharts();

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

// Registrar para eventos futuros
document.addEventListener("rails_admin.dom_ready", initDashboard);
document.addEventListener("turbo:load", initDashboard);

// Si el DOM ya está listo, ejecutar inmediatamente
if (document.readyState !== 'loading') {
  initDashboard();
} else {
  document.addEventListener("DOMContentLoaded", initDashboard);
}

// ── Contadores animados (count-up) ──────────────────────────────────
function initCountUpAnimations() {
  document.querySelectorAll('.countup').forEach(el => {
    const target = parseInt(el.dataset.target) || 0;
    if (target === 0) return;

    const duration = 1500;
    const startTime = performance.now();
    el.textContent = '0';

    function update(currentTime) {
      const elapsed = currentTime - startTime;
      const progress = Math.min(elapsed / duration, 1);
      // Easing: ease-out cubic
      const eased = 1 - Math.pow(1 - progress, 3);
      el.textContent = Math.round(eased * target).toLocaleString('es-VE');
      if (progress < 1) requestAnimationFrame(update);
    }
    requestAnimationFrame(update);
  });
}

// ── Radial Gauge: Tasa de Aprobación ────────────────────────────────
function initApprovalGauge() {
  const el = document.querySelector('#chart-approval');
  if (!el) return;

  const rate = parseInt(el.dataset.rate) || 0;
  let color = '#198754'; // success
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
  const el = document.querySelector('#chart-enrollment');
  if (!el) return;

  const data = JSON.parse(el.dataset.chart);
  createChart(el, {
    chart: {
      type: 'bar', height: 280, stacked: true,
      toolbar: { show: false },
      animations: { enabled: true, speed: 800, animateGradually: { enabled: true, delay: 150 } }
    },
    plotOptions: { bar: { horizontal: true, barHeight: '55%', borderRadius: 3 } },
    colors: ['#198754', '#0d6efd', '#ffc107'],
    series: [
      { name: 'Confirmados', data: data.confirmado },
      { name: 'Preinscritos', data: data.preinscrito },
      { name: 'Reservados', data: data.reservado }
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
  const el = document.querySelector('#chart-qualifications');
  if (!el) return;

  const data = JSON.parse(el.dataset.chart);
  createChart(el, {
    chart: {
      type: 'donut', height: 280,
      animations: { enabled: true, speed: 800, animateGradually: { enabled: true, delay: 200 } }
    },
    labels: data.labels,
    series: data.values,
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
  const el = document.querySelector('#spark-enrollment');
  if (!el) return;

  const values = JSON.parse(el.dataset.values);
  if (!values || values.length < 2) return;

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
  const indicator = document.querySelector('#live-indicator');
  if (!indicator) return;

  const lastUpdated = document.querySelector('#last-updated');
  let secondsAgo = 0;

  // Actualizar texto "hace Xs"
  setInterval(function () {
    secondsAgo++;
    if (lastUpdated) {
      if (secondsAgo < 60) {
        lastUpdated.textContent = 'Hace ' + secondsAgo + 's';
      } else {
        lastUpdated.textContent = 'Hace ' + Math.floor(secondsAgo / 60) + 'min';
      }
    }
  }, 1000);

  // Fetch datos cada 30 segundos
  setInterval(function () {
    fetch('/admin_dashboard/enrollment_counts')
      .then(function (r) { return r.json(); })
      .then(function (data) {
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
                animateSingleCounter(el, values[i]);
              }
            });
          }
        }
      })
      .catch(function () { /* silenciar errores de red */ });
  }, 30000);
}

function animateSingleCounter(el, target) {
  var current = parseInt(el.textContent.replace(/\./g, '')) || 0;
  var duration = 800;
  var startTime = performance.now();

  function update(currentTime) {
    var elapsed = currentTime - startTime;
    var progress = Math.min(elapsed / duration, 1);
    var eased = 1 - Math.pow(1 - progress, 3);
    el.textContent = Math.round(current + (target - current) * eased).toLocaleString('es-VE');
    if (progress < 1) requestAnimationFrame(update);
  }
  requestAnimationFrame(update);
}
