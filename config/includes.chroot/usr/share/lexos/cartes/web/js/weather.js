// weather.js — LexOS Maps
// Météo par secteur : découpe la zone visible en une grille et affiche la
// température/condition actuelle de chaque secteur (source : Open-Meteo,
// gratuit, sans clé d'API). Le fuseau horaire de chaque secteur est
// récupéré dans la même requête (paramètre timezone=auto d'Open-Meteo).

import * as maplibregl from 'https://unpkg.com/maplibre-gl@6.0.0/dist/maplibre-gl.mjs';
import { state as mapState, getViewportSectors } from './map.js';
import { debounce, formatLocalTime } from './ui.js';

const GRID_SIZE = 3;
const REFRESH_DEBOUNCE_MS = 700;
const WEATHER_ENDPOINT = 'https://api.open-meteo.com/v1/forecast';

// Codes météo WMO (utilisés par Open-Meteo) → icône + libellé court en français.
const WMO_CODES = {
  0: ['☀️', 'Ciel dégagé'],
  1: ['🌤️', 'Généralement dégagé'],
  2: ['⛅', 'Partiellement nuageux'],
  3: ['☁️', 'Couvert'],
  45: ['🌫️', 'Brouillard'],
  48: ['🌫️', 'Brouillard givrant'],
  51: ['🌦️', 'Bruine légère'],
  53: ['🌦️', 'Bruine'],
  55: ['🌦️', 'Bruine dense'],
  56: ['🌧️', 'Bruine verglaçante'],
  57: ['🌧️', 'Bruine verglaçante dense'],
  61: ['🌧️', 'Pluie légère'],
  63: ['🌧️', 'Pluie'],
  65: ['🌧️', 'Forte pluie'],
  66: ['🌧️', 'Pluie verglaçante'],
  67: ['🌧️', 'Forte pluie verglaçante'],
  71: ['🌨️', 'Neige légère'],
  73: ['🌨️', 'Neige'],
  75: ['❄️', 'Forte neige'],
  77: ['❄️', 'Grains de neige'],
  80: ['🌦️', "Averses légères"],
  81: ['🌧️', 'Averses'],
  82: ['⛈️', 'Averses violentes'],
  85: ['🌨️', 'Averses de neige'],
  86: ['❄️', 'Fortes averses de neige'],
  95: ['⛈️', 'Orage'],
  96: ['⛈️', 'Orage avec grêle'],
  99: ['⛈️', 'Orage avec forte grêle'],
};

function describeCode(code) {
  return WMO_CODES[code] || ['❓', 'Inconnu'];
}

let markers = [];
let enabled = true;
let requestSeq = 0;

function clearMarkers() {
  markers.forEach((m) => m.remove());
  markers = [];
}

async function fetchSector(sector) {
  const url = new URL(WEATHER_ENDPOINT);
  url.searchParams.set('latitude', sector.lat.toFixed(3));
  url.searchParams.set('longitude', sector.lon.toFixed(3));
  url.searchParams.set('current', 'temperature_2m,weather_code,wind_speed_10m');
  url.searchParams.set('timezone', 'auto');

  const res = await fetch(url.toString());
  if (!res.ok) throw new Error(`Open-Meteo a répondu ${res.status}`);
  const data = await res.json();
  return { sector, data };
}

function renderSector({ sector, data }) {
  const map = mapState.map;
  const current = data.current || {};
  const [icon, label] = describeCode(current.weather_code);
  const temp = typeof current.temperature_2m === 'number' ? Math.round(current.temperature_2m) : '–';

  const el = document.createElement('div');
  el.className = 'lexos-weather-badge';
  el.innerHTML = `<span class="lexos-weather-badge__icon">${icon}</span><span class="lexos-weather-badge__temp">${temp}°</span>`;

  const localTime = data.utc_offset_seconds != null ? formatLocalTime(data.utc_offset_seconds) : '—';
  const popupHTML = `
    <div class="lexos-weather-popup">
      <strong>${label}</strong><br/>
      ${temp}°C · vent ${Math.round(current.wind_speed_10m || 0)} km/h<br/>
      Fuseau : ${data.timezone || 'inconnu'}<br/>
      Heure locale : ${localTime}
    </div>`;

  const marker = new maplibregl.Marker({ element: el, anchor: 'center' })
    .setLngLat([sector.lon, sector.lat])
    .setPopup(new maplibregl.Popup({ offset: 18, closeButton: false }).setHTML(popupHTML))
    .addTo(map);

  markers.push(marker);
}

async function refresh() {
  if (!enabled || !mapState.map) return;
  const mySeq = ++requestSeq;
  const sectors = getViewportSectors(GRID_SIZE);

  const results = await Promise.allSettled(sectors.map(fetchSector));
  if (mySeq !== requestSeq) return; // une requête plus récente est en cours, on jette celle-ci

  clearMarkers();
  for (const r of results) {
    if (r.status === 'fulfilled') renderSector(r.value);
    else console.warn('[LexOS] Secteur météo indisponible:', r.reason?.message);
  }
}

const debouncedRefresh = debounce(refresh, REFRESH_DEBOUNCE_MS);

export function initWeather() {
  const map = mapState.map;
  if (!map) return;

  const start = () => {
    refresh();
    map.on('moveend', debouncedRefresh);
    document.getElementById('lexos-weather-toggle')?.addEventListener('click', toggleWeather);
  };

  if (map.isStyleLoaded()) start();
  else map.getContainer().addEventListener('lexos:map-ready', start, { once: true });
}

export function toggleWeather() {
  enabled = !enabled;
  const btn = document.getElementById('lexos-weather-toggle');
  if (btn) btn.classList.toggle('lexos-btn--active', enabled);
  if (enabled) refresh();
  else clearMarkers();
  return enabled;
}
