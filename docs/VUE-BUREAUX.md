# Vue des bureaux et applications

Le bouton portrait fixe de 96 × 116 pixels se trouve en bas à droite,
au pied du dock. Il ouvre `lexos-overview` ; Échap ferme cette vue.
Les nouvelles installations proposent deux bureaux, sans modifier le nombre
de bureaux des comptes déjà existants.

La partie haute montre les bureaux et leurs fenêtres : cliquer sur un bureau
le sélectionne ; cliquer sur une fenêtre l'active. Les miniatures utilisent la
capture X11 fournie par Qt. Une fenêtre masquée ou inaccessible peut ne fournir
aucune miniature ; son titre reste accessible. `wmctrl` est requis pour la
liste des bureaux et les changements de fenêtre.

La partie basse présente la température du premier GPU NVIDIA, sa mémoire
vidéo utilisée et l'espace du disque contenant `/`. Les lectures ont lieu toutes
les deux secondes dans un fil de travail, seulement pendant l'ouverture de la
vue. L'aiguille rejoint la mesure avec une animation. Les valeurs indisponibles
ne sont pas remplacées par des mesures inventées. Dans une VM sans accès direct
au GPU NVIDIA, température et VRAM restent indisponibles. L'espace affiché en
session live est celui de la racine live, pas celui du disque Windows.

Les applications sont lues dans les dossiers XDG, avec respect des entrées
masquées et des restrictions du bureau. Les pages contiennent douze applications
et changent à la molette verticale ou par les flèches. Le lancement passe par
`gio launch`, qui interprète les entrées desktop sans exécuter une commande shell
construite à partir du nom d'application.

Le bouton agrandi accompagne la position par défaut du dock (droite).
Il reste en bas à droite si le dock est déplacé. Le portrait fourni est conservé
sur fond noir et converti en vrai PNG pour les outils de construction.
