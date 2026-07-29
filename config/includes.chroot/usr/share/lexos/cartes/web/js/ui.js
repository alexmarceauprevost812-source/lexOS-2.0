// ui.js — LexOS Maps
// Petits utilitaires d'interface partagés entre les modules (toasts, etc.)

let toastTimer = null;

export function showToast(message, { duration = 2600, isError = false } = {}) {
  let el = document.getElementById('lexos-toast');
  if (!el) {
    el = document.createElement('div');
    el.id = 'lexos-toast';
    document.body.appendChild(el);
  }
  el.textContent = message;
  el.classList.toggle('lexos-toast--error', !!isError);
  el.classList.add('lexos-toast--visible');

  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    el.classList.remove('lexos-toast--visible');
  }, duration);
}

export function formatCoord(value, isLat) {
  const dir = isLat ? (value >= 0 ? 'N' : 'S') : value >= 0 ? 'E' : 'O';
  return `${Math.abs(value).toFixed(4)}° ${dir}`;
}

/** Formatte une heure locale à partir d'un décalage UTC en secondes. */
export function formatLocalTime(utcOffsetSeconds, date = new Date()) {
  const utcMs = date.getTime() + date.getTimezoneOffset() * 60000;
  const local = new Date(utcMs + utcOffsetSeconds * 1000);
  const hh = String(local.getHours()).padStart(2, '0');
  const mm = String(local.getMinutes()).padStart(2, '0');
  return `${hh}:${mm}`;
}

export function debounce(fn, wait = 400) {
  let t = null;
  return (...args) => {
    clearTimeout(t);
    t = setTimeout(() => fn(...args), wait);
  };
}
