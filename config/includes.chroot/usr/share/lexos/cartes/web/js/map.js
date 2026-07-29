// map.js — LexOS Maps
// Initialise la carte MapLibre GL (données réelles OpenStreetMap servies par
// OpenFreeMap, gratuit et sans clé d'API) et branche le thème jour/nuit.

import * as maplibregl from 'https://unpkg.com/maplibre-gl@6.0.0/dist/maplibre-gl.mjs';
import { THEMES, applyTheme, nextTheme } from './theme.js';

// Style de base réel (schéma OpenMapTiles). On repeint ensuite ses calques
// avec theme.js plutôt que de réécrire ~100 calques à la main : plus fiable
// et toujours synchronisé avec les vraies données/POI/labels d'OpenFreeMap.
const BASE_STYLE_URL = 'https://tiles.openfreemap.org/styles/liberty';

export const state = {
  map: null,
  theme: 'night',
  ready: false,
};

export function initMap({ container, center = [-79.38, 43.65], zoom = 11, theme = 'night' } = {}) {
  const map = new maplibregl.Map({
    container,
    style: BASE_STYLE_URL,
    center,
    zoom,
    attributionControl: false,
    canvasContextAttributes: { preserveDrawingBuffer: true }, // requis pour l'export image (partage)
  });

  map.addControl(new maplibregl.NavigationControl({ visualizePitch: true }), 'top-right');
  map.addControl(
    new maplibregl.AttributionControl({
      compact: true,
      customAttribution: '© OpenStreetMap • données via OpenFreeMap',
    }),
    'bottom-right'
  );
  map.addControl(new maplibregl.ScaleControl({ unit: 'metric' }), 'bottom-left');

  state.map = map;
  state.theme = theme;

  map.on('load', () => {
    addAddressLayer(map);
    applyTheme(map, state.theme);
    state.ready = true;
    map.getContainer().dispatchEvent(new CustomEvent('lexos:map-ready', { bubbles: true }));
  });

  // Certaines tuiles/labels arrivent après le 1er "load" : on repasse le
  // thème dessus pour rester cohérent (idempotent, pas cher).
  map.on('styledata', () => {
    if (state.ready) applyTheme(map, state.theme);
  });

  return map;
}

/** Ajoute les numéros civiques (adresses) — absents du style Liberty de base. */
function addAddressLayer(map) {
  if (map.getLayer('lexos-housenumbers')) return;
  try {
    map.addLayer({
      id: 'lexos-housenumbers',
      type: 'symbol',
      source: 'openmaptiles',
      'source-layer': 'housenumber',
      minzoom: 17,
      layout: {
        'text-field': ['get', 'housenumber'],
        'text-font': ['Noto Sans Regular'],
        'text-size': 10,
        'text-anchor': 'center',
      },
      paint: {
        'text-color': THEMES[state.theme].text,
        'text-halo-color': THEMES[state.theme].textHalo,
        'text-halo-width': 1,
      },
    });
  } catch (err) {
    console.warn('[LexOS] Calque des adresses indisponible sur cette source de tuiles:', err.message);
  }
}

export function toggleTheme() {
  if (!state.map) return state.theme;
  state.theme = nextTheme(state.theme);
  applyTheme(state.map, state.theme);
  return state.theme;
}

export function setTheme(themeName) {
  if (!state.map || !THEMES[themeName]) return state.theme;
  state.theme = themeName;
  applyTheme(state.map, state.theme);
  return state.theme;
}

/** Découpe la zone visible actuelle en une grille de secteurs (pour la météo). */
export function getViewportSectors(gridSize = 3) {
  const map = state.map;
  if (!map) return [];
  const bounds = map.getBounds();
  const west = bounds.getWest();
  const east = bounds.getEast();
  const south = bounds.getSouth();
  const north = bounds.getNorth();

  const sectors = [];
  for (let row = 0; row < gridSize; row++) {
    for (let col = 0; col < gridSize; col++) {
      const lon = west + ((col + 0.5) * (east - west)) / gridSize;
      const lat = south + ((row + 0.5) * (north - south)) / gridSize;
      sectors.push({
        id: `${row}-${col}`,
        lat,
        lon,
        point: map.project([lon, lat]),
      });
    }
  }
  return sectors;
}
