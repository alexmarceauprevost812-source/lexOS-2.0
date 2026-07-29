// position.js — LexOS Maps
// Position actuelle sur la carte + partage (lien ou image) avec quelqu'un
// d'autre. Le point de position est dessiné comme calque MapLibre (pas un
// marqueur HTML) afin qu'il apparaisse aussi dans l'export image.

import { state as mapState } from './map.js';
import { showToast, formatCoord } from './ui.js';

const SOURCE_ID = 'lexos-position';
const SOURCE_SHARED_ID = 'lexos-shared-position';

let watchId = null;
let lastPosition = null; // { lat, lon }

function ensureSources(map) {
  if (!map.getSource(SOURCE_ID)) {
    map.addSource(SOURCE_ID, { type: 'geojson', data: emptyFC() });
    map.addLayer({
      id: 'lexos-position-halo',
      type: 'circle',
      source: SOURCE_ID,
      paint: {
        'circle-radius': 16,
        'circle-color': '#4da3ff',
        'circle-opacity': 0.25,
      },
    });
    map.addLayer({
      id: 'lexos-position-dot',
      type: 'circle',
      source: SOURCE_ID,
      paint: {
        'circle-radius': 7,
        'circle-color': '#2e78e4',
        'circle-stroke-width': 2,
        'circle-stroke-color': '#ffffff',
      },
    });
  }
  if (!map.getSource(SOURCE_SHARED_ID)) {
    map.addSource(SOURCE_SHARED_ID, { type: 'geojson', data: emptyFC() });
    map.addLayer({
      id: 'lexos-shared-position-dot',
      type: 'circle',
      source: SOURCE_SHARED_ID,
      paint: {
        'circle-radius': 8,
        'circle-color': '#ac1e22',
        'circle-stroke-width': 2,
        'circle-stroke-color': '#ffffff',
      },
    });
  }
}

function emptyFC() {
  return { type: 'FeatureCollection', features: [] };
}

function pointFC(lat, lon) {
  return {
    type: 'FeatureCollection',
    features: [{ type: 'Feature', geometry: { type: 'Point', coordinates: [lon, lat] }, properties: {} }],
  };
}

function updateBadge(lat, lon) {
  const badge = document.getElementById('lexos-position-readout');
  if (badge) badge.textContent = `${formatCoord(lat, true)}  ${formatCoord(lon, false)}`;
}

export function initPosition() {
  const map = mapState.map;
  if (!map) return;

  const wire = () => {
    ensureSources(map);
    startWatching();
    applySharedFromURL();

    document.getElementById('lexos-locate-btn')?.addEventListener('click', () => {
      if (!lastPosition) {
        showToast("Position pas encore disponible — vérifie l'accès à la localisation.", { isError: true });
        return;
      }
      map.flyTo({ center: [lastPosition.lon, lastPosition.lat], zoom: Math.max(map.getZoom(), 14) });
    });

    document.getElementById('lexos-share-link-btn')?.addEventListener('click', shareLink);
    document.getElementById('lexos-share-image-btn')?.addEventListener('click', shareImage);
  };

  if (map.isStyleLoaded()) wire();
  else map.getContainer().addEventListener('lexos:map-ready', wire, { once: true });
}

function startWatching() {
  if (!('geolocation' in navigator)) {
    showToast('Géolocalisation non disponible dans ce navigateur.', { isError: true });
    return;
  }
  watchId = navigator.geolocation.watchPosition(onPosition, onPositionError, {
    enableHighAccuracy: true,
    maximumAge: 5000,
    timeout: 15000,
  });
}

function onPosition(pos) {
  const { latitude: lat, longitude: lon } = pos.coords;
  lastPosition = { lat, lon };
  const map = mapState.map;
  if (map && map.getSource(SOURCE_ID)) {
    map.getSource(SOURCE_ID).setData(pointFC(lat, lon));
  }
  updateBadge(lat, lon);
}

function onPositionError(err) {
  console.warn('[LexOS] Géolocalisation refusée/indisponible:', err.message);
  showToast('Active la localisation pour voir ta position sur la carte.', { isError: true });
}

/** Construit un lien qui rouvre LexOS centré sur une position précise. */
function buildShareURL(lat, lon, zoom) {
  const url = new URL(window.location.href);
  url.searchParams.set('lat', lat.toFixed(6));
  url.searchParams.set('lon', lon.toFixed(6));
  url.searchParams.set('zoom', zoom.toFixed(2));
  return url.toString();
}

async function shareLink() {
  const map = mapState.map;
  const point = lastPosition || { lat: map.getCenter().lat, lon: map.getCenter().lng };
  const url = buildShareURL(point.lat, point.lon, map.getZoom());

  if (navigator.share) {
    try {
      await navigator.share({ title: 'Ma position — LexOS', text: 'Voici où je suis sur LexOS', url });
      return;
    } catch (err) {
      if (err.name === 'AbortError') return; // l'utilisateur a annulé
    }
  }
  try {
    await navigator.clipboard.writeText(url);
    showToast('Lien de position copié dans le presse-papiers !');
  } catch {
    showToast(url, { duration: 6000 });
  }
}

function shareImage() {
  const map = mapState.map;
  try {
    map.once('render', () => {}); // no-op, force un frame prêt
    const dataURL = map.getCanvas().toDataURL('image/png');
    const link = document.createElement('a');
    const stamp = new Date().toISOString().replace(/[:.]/g, '-');
    link.href = dataURL;
    link.download = `lexos-position-${stamp}.png`;
    document.body.appendChild(link);
    link.click();
    link.remove();
    showToast('Image de la carte exportée.');
  } catch (err) {
    console.error(err);
    showToast("Impossible d'exporter l'image (WebGL preserveDrawingBuffer).", { isError: true });
  }
}

/** Si l'URL contient ?lat=&lon=(&zoom=), centre la carte et pose un repère "partagé". */
function applySharedFromURL() {
  const params = new URLSearchParams(window.location.search);
  const lat = parseFloat(params.get('lat'));
  const lon = parseFloat(params.get('lon'));
  const zoom = parseFloat(params.get('zoom'));
  if (Number.isNaN(lat) || Number.isNaN(lon)) return;

  const map = mapState.map;
  map.jumpTo({ center: [lon, lat], zoom: Number.isNaN(zoom) ? 14 : zoom });
  if (map.getSource(SOURCE_SHARED_ID)) {
    map.getSource(SOURCE_SHARED_ID).setData(pointFC(lat, lon));
  }
  showToast('Position partagée reçue — repère rouge sur la carte.');
}

export function stopWatching() {
  if (watchId !== null && 'geolocation' in navigator) {
    navigator.geolocation.clearWatch(watchId);
    watchId = null;
  }
}
