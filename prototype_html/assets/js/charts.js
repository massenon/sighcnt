/* =============================================================================
 * SIGH-CNT — Graphiques (Chart.js vendoré)
 * -----------------------------------------------------------------------------
 * Palette dérivée de la charte CDCT §10.3. Toutes les fonctions dégradent
 * proprement si Chart.js est absent : un état de repli est affiché, aucune
 * erreur JS n'est levée.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, el = C.el;

  var PALETTE = ['#12315e', '#3765a6', '#6c9ed4', '#22a170', '#f98307', '#ef4444', '#9dc0e4', '#12684a', '#b74106', '#7f1d1d'];
  var TONES = {
    navy: '#12315e', bleu: '#3765a6', ciel: '#6c9ed4',
    vert: '#22a170', orange: '#f98307', rouge: '#ef4444', gris: '#94a3b8',
  };

  function ready() { return typeof global.Chart !== 'undefined'; }

  function fallback(message) {
    return el('div.flex.h-full.min-h-\\[12rem\\].flex-col.items-center.justify-center.gap-2.rounded-lg.border.border-dashed.border-slate-300.text-center', null, [
      el('span.text-slate-400', null, C.icon('bar-chart-3', 'h-6 w-6')),
      el('p.text-xs.text-slate-500', { text: message || 'Graphique indisponible.' }),
    ]);
  }

  var baseOptions = {
    responsive: true,
    maintainAspectRatio: false,
    interaction: { mode: 'index', intersect: false },
    plugins: {
      legend: {
        display: true, position: 'bottom',
        labels: { boxWidth: 10, boxHeight: 10, usePointStyle: true, pointStyle: 'circle', font: { family: 'Inter', size: 11 }, color: '#64748b', padding: 14 },
      },
      tooltip: {
        backgroundColor: '#0b1e3d', padding: 10, cornerRadius: 8, displayColors: true, boxPadding: 4,
        titleFont: { family: 'Inter', size: 12 }, bodyFont: { family: 'Inter', size: 12 },
        callbacks: {
          label: function (ctx) {
            var v = ctx.parsed.y != null ? ctx.parsed.y : ctx.parsed;
            return ' ' + ctx.dataset.label + ' : ' + C.num(v);
          },
        },
      },
    },
    scales: {
      x: { grid: { display: false }, ticks: { font: { family: 'Inter', size: 11 }, color: '#94a3b8' }, border: { color: '#e2e8f0' } },
      y: {
        beginAtZero: true, grid: { color: '#f1f5f9' }, border: { display: false },
        ticks: { font: { family: 'Inter', size: 11 }, color: '#94a3b8', callback: function (v) { return C.num(v); } },
      },
    },
  };

  function merge(a, b) {
    var out = Object.assign({}, a);
    Object.keys(b || {}).forEach(function (k) {
      out[k] = (b[k] && typeof b[k] === 'object' && !Array.isArray(b[k])) ? merge(a[k] || {}, b[k]) : b[k];
    });
    return out;
  }

  /** Conteneur canvas à hauteur fixe. */
  function host(height) {
    return el('div.relative', { style: 'height:' + (height || 260) + 'px;' });
  }

  function build(type, labels, datasets, opts, height) {
    var wrap = host(height);
    if (!ready()) { wrap.appendChild(fallback('Bibliothèque de graphiques non chargée.')); return wrap; }
    var canvas = el('canvas');
    wrap.appendChild(canvas);
    /* Le rendu est différé pour que le canvas soit dans le DOM (dimensions). */
    setTimeout(function () {
      try {
        new global.Chart(canvas.getContext('2d'), {
          type: type,
          data: { labels: labels, datasets: datasets },
          options: merge(baseOptions, opts || {}),
        });
      } catch (e) {
        console.error('[SIGH] Graphique :', e);
        C.clear(wrap); wrap.appendChild(fallback('Erreur de rendu du graphique.'));
      }
    }, 0);
    return wrap;
  }

  /* --- Fabriques ---------------------------------------------------------- */
  function ligne(labels, series, opts) {
    var ds = series.map(function (s, i) {
      var col = s.color || PALETTE[i % PALETTE.length];
      return {
        label: s.label, data: s.data, borderColor: col,
        backgroundColor: s.fill === false ? 'transparent' : col + '22',
        fill: s.fill !== false, tension: 0.35, borderWidth: 2,
        pointRadius: 0, pointHoverRadius: 4, pointBackgroundColor: col,
      };
    });
    return build('line', labels, ds, opts, (opts && opts.height) || 260);
  }

  function barres(labels, series, opts) {
    var o = opts || {};
    var ds = series.map(function (s, i) {
      return {
        label: s.label, data: s.data,
        backgroundColor: s.color || PALETTE[i % PALETTE.length],
        borderRadius: 4, borderSkipped: false,
        maxBarThickness: o.horizontal ? 22 : 38,
      };
    });
    var extra = o.horizontal ? { indexAxis: 'y', scales: { x: { beginAtZero: true, grid: { color: '#f1f5f9' } }, y: { grid: { display: false } } } } : {};
    if (o.stack) extra.scales = merge(extra.scales || {}, { x: { stacked: true }, y: { stacked: true } });
    return build('bar', labels, ds, merge(extra, o), o.height || 260);
  }

  function anneau(labels, data, opts) {
    var o = opts || {};
    var ds = [{
      label: o.label || 'Répartition', data: data,
      backgroundColor: o.colors || PALETTE, borderWidth: 2, borderColor: '#fff', hoverOffset: 6,
    }];
    return build('doughnut', labels, ds, merge({
      cutout: o.cutout || '62%',
      scales: { x: { display: false }, y: { display: false } },
      plugins: {
        legend: { position: o.legend || 'right' },
        tooltip: {
          callbacks: {
            label: function (ctx) {
              var tot = ctx.dataset.data.reduce(function (a, b) { return a + b; }, 0) || 1;
              return ' ' + ctx.label + ' : ' + C.num(ctx.parsed) + ' (' + C.pct(ctx.parsed / tot * 100) + ')';
            },
          },
        },
      },
    }, o), o.height || 260);
  }

  function camembert(labels, data, opts) {
    return anneau(labels, data, merge({ cutout: 0 }, opts || {}));
  }

  /** Sparkline compacte pour les cartes KPI. */
  function sparkline(data, color) {
    var wrap = el('div.relative', { style: 'height:40px;' });
    if (!ready()) return wrap;
    var canvas = el('canvas');
    wrap.appendChild(canvas);
    setTimeout(function () {
      try {
        new global.Chart(canvas.getContext('2d'), {
          type: 'line',
          data: {
            labels: data.map(function (_, i) { return i; }),
            datasets: [{
              data: data, borderColor: color || TONES.navy, borderWidth: 2,
              backgroundColor: (color || TONES.navy) + '18', fill: true, tension: 0.4, pointRadius: 0,
            }],
          },
          options: {
            responsive: true, maintainAspectRatio: false,
            plugins: { legend: { display: false }, tooltip: { enabled: false } },
            scales: { x: { display: false }, y: { display: false } },
          },
        });
      } catch (e) { /* sans effet visible */ }
    }, 0);
    return wrap;
  }

  /** Douze derniers mois, libellés courts. */
  function moisGlissants(n) {
    var out = [], d = new Date(2026, 7, 1);
    for (var i = (n || 12) - 1; i >= 0; i--) {
      var m = new Date(d.getFullYear(), d.getMonth() - i, 1);
      out.push(C.MOIS[m.getMonth()].slice(0, 4) + '. ' + String(m.getFullYear()).slice(-2));
    }
    return out;
  }

  global.SIGH.charts = {
    PALETTE: PALETTE, TONES: TONES, ready: ready,
    ligne: ligne, barres: barres, anneau: anneau, camembert: camembert,
    sparkline: sparkline, moisGlissants: moisGlissants, fallback: fallback,
  };
})(window);
