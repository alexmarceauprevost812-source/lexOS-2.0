// theme.js — LexOS Maps
// Définit les thèmes jour/nuit et applique les couleurs sur le style MapLibre
// (basé sur le style réel "Liberty" d'OpenFreeMap : mêmes id de calques,
// on ne fait que repeindre les propriétés "paint").
//
// Thème NUIT  : autoroutes bleu foncé, routes normales orange,
//               chemins forestiers/sentiers en rouge (couleur prélevée
//               sur l'image de référence fournie : #ac1e22).
// Thème JOUR  : fond beige foncé, routes claires neutres.

export const THEMES = {
  night: {
    id: 'night',
    label: 'Nuit',
    background: '#0d1420',
    text: '#e8e4da',
    textHalo: '#05070c',
    fallback: {
      water: '#0f1f35',
      land: 'hsla(100,20%,14%,0.85)',
      building: '#1c2230',
    },
    // Overrides précis, un-à-un, des calques réels du style Liberty.
    layers: {
      background: { 'background-color': '#0d1420' },
      water: { 'fill-color': '#0f1f35' },
      landcover_wood: { 'fill-color': 'hsla(100,25%,16%,0.85)' },
      park: { 'fill-color': '#182a1c' },
      building: { 'fill-color': '#1c2230' },
      boundary_2: { 'line-color': '#3a4558' },

      // --- Autoroutes → joli bleu foncé ---
      road_motorway: { 'line-color': '#2a4d8f' },
      road_motorway_link: { 'line-color': '#2a4d8f' },
      bridge_motorway: { 'line-color': '#2a4d8f' },
      bridge_motorway_link: { 'line-color': '#2a4d8f' },
      tunnel_motorway: { 'line-color': '#1c355f' },
      tunnel_motorway_link: { 'line-color': '#1c355f' },

      // --- Routes normales (primaire/secondaire/locale) → orange ---
      road_trunk_primary: { 'line-color': '#e8871e' },
      bridge_trunk_primary: { 'line-color': '#e8871e' },
      tunnel_trunk_primary: { 'line-color': '#7a4a1a' },
      road_secondary_tertiary: { 'line-color': '#e8871e' },
      bridge_secondary_tertiary: { 'line-color': '#e8871e' },
      tunnel_secondary_tertiary: { 'line-color': '#7a4a1a' },
      road_minor: { 'line-color': '#eda23f' },
      bridge_street: { 'line-color': '#eda23f' },
      tunnel_minor: { 'line-color': '#7a4a1a' },
      road_link: { 'line-color': '#e8871e' },
      bridge_link: { 'line-color': '#e8871e' },
      tunnel_link: { 'line-color': '#7a4a1a' },

      // --- Chemins forestiers / sentiers / non pavés → rouge ---
      road_service_track: { 'line-color': '#ac1e22' },
      bridge_service_track: { 'line-color': '#ac1e22' },
      tunnel_service_track: { 'line-color': '#6e1315' },
      road_path_pedestrian: { 'line-color': '#c33a3e' },
      bridge_path_pedestrian: { 'line-color': '#c33a3e' },
      tunnel_path_pedestrian: { 'line-color': '#6e1315' },

      road_major_rail: { 'line-color': '#5a6472' },
      road_transit_rail: { 'line-color': '#5a6472' },
    },
  },

  day: {
    id: 'day',
    label: 'Jour',
    background: '#413a2d',
    text: '#f2ecd9',
    textHalo: '#241f17',
    fallback: {
      water: '#33424a',
      land: 'hsla(80,20%,30%,0.55)',
      building: '#5a5040',
    },
    layers: {
      // --- Fond : joli beige foncé (façon Claude AI) ---
      background: { 'background-color': '#413a2d' },
      water: { 'fill-color': '#33424a' },
      landcover_wood: { 'fill-color': 'hsla(90,25%,28%,0.6)' },
      park: { 'fill-color': '#3a4a34' },
      building: { 'fill-color': '#5a5040' },
      boundary_2: { 'line-color': '#8a7d64' },

      // Routes neutres et claires (pas de code couleur spécial demandé
      // pour le jour — seulement l'ambiance beige foncé).
      road_motorway: { 'line-color': '#f2d9a1' },
      road_motorway_link: { 'line-color': '#f2d9a1' },
      bridge_motorway: { 'line-color': '#f2d9a1' },
      bridge_motorway_link: { 'line-color': '#f2d9a1' },
      tunnel_motorway: { 'line-color': '#8a7550' },
      tunnel_motorway_link: { 'line-color': '#8a7550' },

      road_trunk_primary: { 'line-color': '#e8dcc4' },
      bridge_trunk_primary: { 'line-color': '#e8dcc4' },
      tunnel_trunk_primary: { 'line-color': '#7a6f57' },
      road_secondary_tertiary: { 'line-color': '#e8dcc4' },
      bridge_secondary_tertiary: { 'line-color': '#e8dcc4' },
      tunnel_secondary_tertiary: { 'line-color': '#7a6f57' },
      road_minor: { 'line-color': '#d9cdb4' },
      bridge_street: { 'line-color': '#d9cdb4' },
      tunnel_minor: { 'line-color': '#7a6f57' },
      road_link: { 'line-color': '#e8dcc4' },
      bridge_link: { 'line-color': '#e8dcc4' },
      tunnel_link: { 'line-color': '#7a6f57' },

      road_service_track: { 'line-color': '#b8ac93' },
      bridge_service_track: { 'line-color': '#b8ac93' },
      tunnel_service_track: { 'line-color': '#6b6350' },
      road_path_pedestrian: { 'line-color': '#c8bc9f' },
      bridge_path_pedestrian: { 'line-color': '#c8bc9f' },
      tunnel_path_pedestrian: { 'line-color': '#6b6350' },

      road_major_rail: { 'line-color': '#9c9280' },
      road_transit_rail: { 'line-color': '#9c9280' },
    },
  },
};

function safeSetPaint(map, layerId, props) {
  if (!map.getLayer(layerId)) return false;
  for (const [prop, value] of Object.entries(props)) {
    try {
      map.setPaintProperty(layerId, prop, value);
    } catch (err) {
      console.warn(`[LexOS] Impossible de repeindre ${layerId}.${prop}:`, err.message);
    }
  }
  return true;
}

/**
 * Applique un thème (jour/nuit) sur une carte MapLibre déjà chargée.
 * 1) Repeint précisément les calques connus du style Liberty.
 * 2) Balaie tous les autres calques (fill/symbol/background/waterway) et
 *    applique une couleur de repli cohérente selon des règles de nommage
 *    standard du schéma OpenMapTiles, pour éviter les zones qui restent
 *    "claires" dans un thème sombre.
 */
export function applyTheme(map, themeName) {
  const theme = THEMES[themeName];
  if (!theme || !map.isStyleLoaded()) return;

  const style = map.getStyle();
  const known = new Set(Object.keys(theme.layers));

  for (const [layerId, props] of Object.entries(theme.layers)) {
    safeSetPaint(map, layerId, props);
  }

  for (const layer of style.layers || []) {
    if (known.has(layer.id)) continue;
    try {
      if (layer.type === 'background') {
        map.setPaintProperty(layer.id, 'background-color', theme.background);
      } else if (layer.type === 'fill') {
        if (/water/i.test(layer.id)) {
          map.setPaintProperty(layer.id, 'fill-color', theme.fallback.water);
        } else if (/building/i.test(layer.id)) {
          map.setPaintProperty(layer.id, 'fill-color', theme.fallback.building);
        } else if (/landcover|landuse|park|wood|grass|sand|ice|farmland|cemetery|hospital|school|pitch|golf|forest/i.test(layer.id)) {
          map.setPaintProperty(layer.id, 'fill-color', theme.fallback.land);
        }
      } else if (layer.type === 'line' && /waterway/i.test(layer.id)) {
        map.setPaintProperty(layer.id, 'line-color', theme.fallback.water);
      } else if (layer.type === 'symbol' && layer.layout && layer.layout['text-field']) {
        map.setPaintProperty(layer.id, 'text-color', theme.text);
        map.setPaintProperty(layer.id, 'text-halo-color', theme.textHalo);
      }
    } catch (err) {
      // Un calque particulier peut refuser une propriété — on continue,
      // ce n'est pas bloquant pour le reste du thème.
    }
  }

  document.body.dataset.theme = themeName;
}

export function nextTheme(current) {
  return current === 'night' ? 'day' : 'night';
}
