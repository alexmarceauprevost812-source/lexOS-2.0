# Sources de dessin — PAS livrées dans l'ISO

`build.sh` recopie `branding/*.svg *.png *.jpg *.jpeg *.webp *.gif *.mp4`
dans l'image. Le `cp` n'est pas récursif : ce sous-dossier n'est donc jamais
copié, et c'est voulu.

On y met les fichiers dont on se sert pour DESSINER, et dont le système en
marche n'a aucun besoin. `icon-files-original.jpg` est le premier : 241 ko,
la photo d'origine qui a servi à tracer `icon-files.svg`, et que rien dans
tout le dépôt ne lit. Elle a failli partir dans l'ISO le jour où la copie
des `.jpg` a été réparée — d'où ce dossier, posé le même jour.
