// timezone.js — LexOS Maps
// Affiche l'heure locale de l'appareil ET l'heure/fuseau horaire du point
// actuellement au centre de la carte (utile pour un endroit lointain).
// Réutilise Open-Meteo (timezone=auto) plutôt qu'une base de fuseaux séparée.

import { state as mapState } from './map.js';
import { debounce } from './ui.js';

let offsetSeconds = null;
let tzName = null;
let tickTimer = null;

function deviceClockString() {
  return new Date().toLocaleTimeString('fr-CA', { hour: '2-digit', minute: '2-digit' });
}

function mapClockString() {
  if (offsetSeconds == null) return '—';
  const now = new Date();
  const utcMs = now.getTime() + now.getTimezoneOffset() * 60000;
  const local = new Date(utcMs + offsetSeconds * 1000);
  return local.toLocaleTimeString('fr-CA', { hour: '2-digit', minute: '2-digit' });
}

function render() {
  const deviceEl = document.getElementById('lexos-clock-device');
  const mapEl = document.getElementById('lexos-clock-map');
  if (deviceEl) deviceEl.textContent = deviceClockString();
  if (mapEl) {
    const tz = tzName || Intl.DateTimeFormat().resolvedOptions().timeZone;
    mapEl.textContent = `${mapClockString()} · ${tz}`;
  }
}

async function fetchTimezoneForCenter() {
  const map = mapState.map;
  if (!map) return;
  const { lat, lng } = map.getCenter();
  try {
    const url = new URL('https://api.open-meteo.com/v1/forecast');
    url.searchParams.set('latitude', lat.toFixed(3));
    url.searchParams.set('longitude', lng.toFixed(3));
    url.searchParams.set('current', 'temperature_2m');
    url.searchParams.set('timezone', 'auto');
    const res = await fetch(url.toString());
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    offsetSeconds = data.utc_offset_seconds;
    tzName = data.timezone;
    render();
  } catch (err) {
    console.warn('[LexOS] Fuseau horaire indisponible pour ce point:', err.message);
  }
}

const debouncedFetch = debounce(fetchTimezoneForCenter, 700);

export function initTimezone() {
  render(); // heure de l'appareil affichée tout de suite, sans réseau
  const map = mapState.map;
  if (!map) return;

  const start = () => {
    fetchTimezoneForCenter();
    map.on('moveend', debouncedFetch);
    tickTimer = setInterval(render, 15000);
  };
  if (map.isStyleLoaded()) start();
  else map.getContainer().addEventListener('lexos:map-ready', start, { once: true });
}

export function stopTimezone() {
  if (tickTimer) clearInterval(tickTimer);
}
