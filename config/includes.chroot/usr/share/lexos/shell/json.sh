# =============================================================================
#  LexOS — échapper une chaîne pour du JSON écrit à la main
# =============================================================================
#  POURQUOI CE FICHIER EXISTE, ET POURQUOI IL EST À PART.
#
#  Les outils de LexOS sont du shell : ils n'ont pas de bibliothèque JSON.
#  Quand la page des Paramètres leur demande leur état, ils écrivent leur
#  JSON à la main — ce qui va très bien tant que les valeurs sortent de NOS
#  tables. Ça cesse d'aller dès qu'une valeur vient d'AILLEURS :
#
#    · le nom d'une application, lu dans un fichier .desktop du système
#      (lexos-defaut), et
#    · le nom complet d'une personne, lu dans le champ GECOS de
#      /etc/passwd (lexos-utilisateurs).
#
#  Un seul guillemet non échappé dans l'un de ces noms, et la page entière
#  reste blanche — sans message, sans erreur, sans rien à quoi se raccrocher.
#  Ce n'est pas une hypothèse d'école : un nom comme « L'« outil » dit
#  "bonjour" » suffit, et le banc des applications par défaut en pose un
#  exprès dans son décor.
#
#  D'où un seul fichier, sur le modèle de secure-boot.sh, et pour la même
#  raison écrite là-bas : deux copies de trois lignes finissent toujours par
#  diverger, et ce dépôt a déjà payé ça cher avec les trois palettes des
#  panneaux web, qui disaient trois choses différentes de la même couleur.
#
#  ═══ CE QU'IL ÉCHAPPE, ET CE QU'IL N'ÉCHAPPE PAS ═══
#  L'antislash D'ABORD, le guillemet ENSUITE — l'ordre inverse doublerait les
#  antislash qu'on vient de poser et transformerait \" en \\".
#
#  Il ne s'occupe PAS des caractères de contrôle (retour à la ligne, tabulation)
#  qui, eux aussi, sont interdits dans une chaîne JSON. Aucun ne peut arriver
#  ici : le champ GECOS et la ligne Name= d'un .desktop sont lus ligne par
#  ligne, ce qui exclut le retour à la ligne, et la tabulation ne survit pas
#  aux séparateurs de ces deux formats. Le jour où une valeur d'une autre
#  provenance passera par ici, c'est CE commentaire qu'il faudra relire.
#
#  ═══ EN POSIX PUR, ET PAS PAR COQUETTERIE ═══
#  Ne pas le « moderniser » avec une substitution bash : les outils de LexOS
#  ne parlent pas tous le même shell, et un fragment qui cesse de fonctionner
#  dans un #!/bin/sh cesse EN SILENCE — la fonction devient simplement
#  introuvable, et l'appelant écrit un JSON vide sans s'en apercevoir.
# =============================================================================
# Ce fragment est SOURCÉ, pas exécuté : pas de shebang, donc shellcheck ne
# peut pas deviner le dialecte. On le lui dit.
# shellcheck shell=sh

json_texte() {
	printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}
