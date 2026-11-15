/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        ink: 'var(--color-ink)',
        paper: 'var(--color-paper)',
        success: 'var(--color-success)',
        pending: 'var(--color-pending)',
        failed: 'var(--color-failed)',
        relief: 'var(--color-relief)',
        cash: 'var(--color-cash)',
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
        mono: ['JetBrains Mono', 'ui-monospace', 'monospace'],
      },
    },
  },
  plugins: [],
};
