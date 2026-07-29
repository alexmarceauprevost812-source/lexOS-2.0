// app.js — LexOS Maps
// Point d'entrée : démarre la carte et branche tous les modules de
// fonctionnalités ensemble.

import { initMap, toggleTheme } from './map.js';
import { initPosition } from './position.js';
import { initWeather } from './weather.js';
import { initTimezone } from './timezone.js';
import { initGlobeLoader } from './globe.js';

function wireThemeToggle() {
  const btn = document.getElementById('lexos-theme-toggle');
  if (!btn) return;
  btn.addEventListener('click', () => {
    const theme = toggleTheme();
    btn.textContent = theme === 'night' ? '🌙 Thème' : '☀️ Thème';
  });
}

function boot() {
  initGlobeLoader(); // démarre l'animation tout de suite, avant même la carte

  initMap({ container: 'map', theme: 'night' });

  initPosition();
  initWeather();
  initTimezone();
  wireThemeToggle();
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', boot);
} else {
  boot();
}
