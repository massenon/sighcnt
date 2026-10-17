/** Tailwind config — SIGH-CNT / Clinique NASSIERA TOO
 *  Charte CDCT §10.3 : bleu institutionnel (navy), fonds blanc/gris clair,
 *  sémantique vert (validé/disponible), orange (alerte), rouge (rupture/erreur).
 *  Build : npm run css  (voir package.json)
 */
module.exports = {
  content: [
    './index.html',
    './pages/**/*.html',
    './build/safelist.html', // classes produites dynamiquement en JS (cf. build/gen-safelist.js)
  ],
  theme: {
    extend: {
      fontFamily: {
        sans: ['Inter', 'Segoe UI', 'system-ui', 'sans-serif'],
        mono: ['Consolas', 'ui-monospace', 'monospace'],
      },
      colors: {
        navy: {
          50: '#f1f5fb', 100: '#e0eaf6', 200: '#c7daf0', 300: '#9dc0e4',
          400: '#6c9ed4', 500: '#4a7fc1', 600: '#3765a6', 700: '#2e5187',
          800: '#2a4670', 900: '#12315e', 950: '#0b1e3d',
        },
        success: {
          50: '#eefbf4', 100: '#d6f5e3', 200: '#b0e9cc', 300: '#7bd7ae',
          400: '#45bd8b', 500: '#22a170', 600: '#15825a', 700: '#12684a',
          800: '#12523c', 900: '#104433',
        },
        warning: {
          50: '#fff8eb', 100: '#ffedc6', 200: '#ffd888', 300: '#ffbe4a',
          400: '#ffa620', 500: '#f98307', 600: '#dd5f02', 700: '#b74106',
          800: '#94320c', 900: '#7a2a0d',
        },
        danger: {
          50: '#fef2f2', 100: '#fee2e2', 200: '#fecaca', 300: '#fca5a5',
          400: '#f87171', 500: '#ef4444', 600: '#dc2626', 700: '#b91c1c',
          800: '#991b1b', 900: '#7f1d1d',
        },
        info: {
          50: '#eff8ff', 100: '#dbeefe', 200: '#bfe2fe', 300: '#92d0fd',
          400: '#61b6fa', 500: '#3b98f6', 600: '#257aeb', 700: '#1d63d8',
          800: '#1e51af', 900: '#1e468a',
        },
      },
      boxShadow: {
        card: '0 1px 2px 0 rgb(11 30 61 / 0.05), 0 1px 3px 0 rgb(11 30 61 / 0.06)',
        raise: '0 4px 12px -2px rgb(11 30 61 / 0.10), 0 2px 6px -2px rgb(11 30 61 / 0.06)',
        pop: '0 12px 32px -8px rgb(11 30 61 / 0.22)',
      },
      keyframes: {
        'fade-in': { '0%': { opacity: '0' }, '100%': { opacity: '1' } },
        'slide-in': { '0%': { transform: 'translateX(100%)' }, '100%': { transform: 'translateX(0)' } },
        'pop-in': { '0%': { opacity: '0', transform: 'scale(.97) translateY(4px)' }, '100%': { opacity: '1', transform: 'scale(1) translateY(0)' } },
      },
      animation: {
        'fade-in': 'fade-in .15s ease-out',
        'slide-in': 'slide-in .2s cubic-bezier(.32,.72,0,1)',
        'pop-in': 'pop-in .16s ease-out',
      },
    },
  },
  plugins: [],
}
