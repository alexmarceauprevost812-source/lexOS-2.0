// globe.js — LexOS Maps
// Écran de chargement : le globe tourne à l'horizontale puis ralentit
// doucement jusqu'à l'arrêt une fois la carte prête (voir style.css pour
// les deux animations @keyframes utilisées ici).

export function initGlobeLoader() {
  const overlay = document.getElementById('lexos-loader');
  const globe = document.getElementById('lexos-loader-globe');
  const mapEl = document.getElementById('map');
  if (!overlay || !globe || !mapEl) return;

  const settle = () => {
    globe.classList.remove('lexos-loader__globe--spin');
    globe.classList.add('lexos-loader__globe--settling');
    setTimeout(() => overlay.classList.add('lexos-loader--hidden'), 900);
    setTimeout(() => overlay.remove(), 1900);
  };

  mapEl.addEventListener('lexos:map-ready', settle, { once: true });

  // Filet de sécurité : si le chargement traîne (réseau lent), on ne bloque
  // pas l'utilisateur indéfiniment derrière l'animation.
  setTimeout(() => {
    if (document.body.contains(overlay)) settle();
  }, 12000);
}
