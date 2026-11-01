/* ════════════════ Les yeux du démon ════════════════
   ALEX (2026-11-01) : les deux yeux rouges en amande du bureau démon
   (nomade-v3), dans l'accueil du Chat. Même forme, ils suivent la souris
   et clignent de temps en temps. Rien ne bouge si le système demande
   moins d'animations. */
(() => {
  const OEIL = "M2 3 C26 8 62 20 97 34 C99 42 92 49 78 50 C56 51 34 42 20 30 C10 21 4 12 2 3 Z";
  const yeux = document.getElementById("yeux-demon");
  if (!yeux) return;
  yeux.querySelectorAll(".oeil-demon-trace").forEach((p) => p.setAttribute("d", OEIL));
  if (matchMedia("(prefers-reduced-motion: reduce)").matches) return;

  const souris = { x: 0, y: 0, attente: false };
  function regarder(lx, ly) {
    yeux.style.transform = `translate(${(lx * 14).toFixed(1)}px,${(ly * 8).toFixed(1)}px) rotate(${(lx * 2).toFixed(1)}deg)`;
  }
  function suivre() {
    souris.attente = false;
    if (!yeux.offsetParent) return;                 // accueil caché : on ne calcule rien
    const r = yeux.getBoundingClientRect();
    const cx = r.left + r.width / 2, cy = r.top + r.height / 2;
    regarder(Math.max(-1, Math.min(1, (souris.x - cx) / (innerWidth / 2))),
             Math.max(-1, Math.min(1, (souris.y - cy) / (innerHeight / 2))));
  }
  addEventListener("mousemove", (e) => {
    souris.x = e.clientX; souris.y = e.clientY;
    if (!souris.attente) { souris.attente = true; requestAnimationFrame(suivre); }
  });
  document.addEventListener("mouseleave", () => regarder(0, 0));

  //  Un clignement au hasard, toutes les 4 à 9 secondes.
  (function cligner() {
    setTimeout(() => {
      if (!document.hidden && yeux.offsetParent) {
        yeux.classList.remove("cligne"); void yeux.offsetWidth; yeux.classList.add("cligne");
      }
      cligner();
    }, 4000 + Math.random() * 5000);
  })();
})();
