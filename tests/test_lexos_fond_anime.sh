#!/usr/bin/env bash
# =============================================================================
#  Éprouver remonte_xfdesktop() — les icônes du bureau derrière le fond animé
# =============================================================================
#  ALEX, photo à l'appui : « quand le fond écran animé (l'écriture de code)
#  tourne, on ne voit pas les applications qu'on met sur le bureau — avec un
#  fond fixe, on les voit ». Puis : « fais en sorte que le fond animé soit
#  capable d'avoir des applications par-dessus, et que le fond animé reste
#  derrière ».
#
#  CE QUI SE PASSAIT VRAIMENT. Notre fenêtre de fond ET xfdesktop (qui
#  dessine les icônes du bureau) sont TOUTES LES DEUX de type
#  _NET_WM_WINDOW_TYPE_DESKTOP. xfwm4 garantit que ce calque reste sous les
#  fenêtres normales — mais PAS l'ordre RELATIF entre deux fenêtres du MÊME
#  calque. Notre fenêtre pouvait donc finir au-dessus de xfdesktop : les
#  icônes disparaissaient derrière le fond animé, sans qu'aucune fenêtre
#  normale ne soit concernée (elles restent bien visibles, elles — c'est
#  pour ça que la photo d'Alex montrait un terminal parfaitement au-dessus
#  du fond, mais pas les icônes du bureau).
#
#  Le correctif : remonte_xfdesktop(), dans fond-anime.py, appelée au
#  démarrage ET à intervalles réguliers (un rechargement de xfdesktop —
#  changement d'accent, par exemple — peut redéfaire l'ordre).
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOTEUR="$RACINE/config/includes.chroot/usr/lib/lexos/fond-anime.py"

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

# =============================================================================
titre "1. remonte_xfdesktop() — xdotool préféré, wmctrl en repli, rien en repli"
# =============================================================================
#  On charge le VRAI module et on lui passe de faux « cherche »/« executeur »
#  — exactement les points d'injection que la fonction offre pour ça. Rien
#  n'est relu à l'œil : c'est le vrai code de fond-anime.py qui tourne ici.
#
#  « reussit » simule le CODE DE SORTIE : quand un des mots donnés (data,
#  séparés par des virgules) est un ÉLÉMENT de la ligne de commande, cet
#  appel « trouve » xfdesktop (code 0) ; sinon il « ne trouve rien » (code
#  1), exactement ce que fait le vrai xdotool sur une recherche à vide.
#  Membre de LISTE, pas sous-chaîne : sans ça, « --class » matcherait aussi
#  « --classname », qui le contient tout entier.
appelle() { # appelle <outils-disponibles-csv> <mots-qui-reussissent-csv>
	python3 -c "
import sys, importlib.util
spec = importlib.util.spec_from_file_location('m', '$MOTEUR')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

dispo = set('$1'.split(',')) if '$1' else set()
reussit = set('$2'.split(',')) if '$2' else set()
appels = []

def cherche(nom):
    return nom in dispo

def executeur(args, **kw):
    appels.append(list(args))
    class R: pass
    r = R()
    r.returncode = 0 if (reussit & set(args)) else 1
    return r

r = m.remonte_xfdesktop(executeur=executeur, cherche=cherche)
print('RESULT=%r' % r)
print('APPELS=%r' % appels)
"
}

#  DEUX CHAMPS, DEUX CASSES : PAS UN SEUL PARI. Une première photo d'Alex a
#  fait passer « --class xfdesktop » à « --classname xfdesktop » (la classe
#  de xfdesktop est capitalisée, « Xfdesktop » — voir le repli wmctrl plus
#  bas). Une DEUXIÈME photo a montré que ça ne suffisait toujours pas :
#  cette session n'a jamais eu de vrai serveur X pour savoir lequel des deux
#  champs de WM_CLASS (et laquelle des deux casses) xfdesktop porte
#  vraiment. La fonction essaie donc « --classname » PUIS « --class », tous
#  deux avec un motif qui accepte les deux capitalisations — et VÉRIFIE LE
#  CODE DE SORTIE à chaque essai, pour ne plus jamais déclarer « réussi »
#  un essai qui n'a rien trouvé (c'était exactement l'ancien bogue : code 0
#  systématique, qu'une fenêtre ait été trouvée ou non).
SORTIE="$(appelle "xdotool,wmctrl" "--classname")"
case "$SORTIE" in
	*"RESULT=True"*"APPELS=[['xdotool', 'search', '--classname', '[Xx]fdesktop', 'windowraise']]"*)
		ok "l'INSTANCE matche du premier coup -> un seul essai, wmctrl jamais appelé" ;;
	*) non "le premier essai (--classname) aurait dû suffire et s'arrêter là : $SORTIE" ;;
esac

SORTIE="$(appelle "xdotool,wmctrl" "--class")"
case "$SORTIE" in
	*"RESULT=True"*"'--classname'"*"'--class'"*"'[Xx]fdesktop'"*)
		ok "l'instance ne matche pas mais la CLASSE oui -> deuxième essai, sans passer par wmctrl" ;;
	*) non "le repli --class (deuxième essai xdotool) n'a pas eu lieu comme attendu : $SORTIE" ;;
esac

#  NI L'UN NI L'AUTRE CHAMP : c'est ici que l'ancien bogue se cachait — la
#  fonction rendait True même quand xdotool n'avait RIEN trouvé. Elle doit
#  maintenant se rabattre sur wmctrl plutôt que de prétendre avoir réussi.
SORTIE="$(appelle "xdotool,wmctrl" "")"
case "$SORTIE" in
	*"RESULT=True"*"'wmctrl'"*"'-x'"*"'-a'"*"'xfdesktop.Xfdesktop'"*)
		ok "xdotool ne trouve rien dans AUCUN des deux champs -> repli sur wmctrl, pas un succès inventé" ;;
	*) non "les deux essais xdotool en échec auraient dû retomber sur wmctrl : $SORTIE" ;;
esac

SORTIE="$(appelle "wmctrl" "")"
case "$SORTIE" in
	*"RESULT=True"*"'wmctrl'"*"'-x'"*"'-a'"*"'xfdesktop.Xfdesktop'"*)
		ok "seul wmctrl dispo -> repli direct sur wmctrl -x -a xfdesktop.Xfdesktop" ;;
	*) non "le repli wmctrl n'a pas eu lieu comme attendu : $SORTIE" ;;
esac

SORTIE="$(appelle "" "")"
case "$SORTIE" in
	*"RESULT=False"*"APPELS=[]"*)
		ok "ni xdotool ni wmctrl -> rien n'est exécuté, et ça le DIT (False), pas un succès inventé" ;;
	*) non "sans outil, la fonction aurait dû rendre False sans rien exécuter : $SORTIE" ;;
esac

# =============================================================================
titre "2. Un outil qui plante ne fait pas tomber le fond d'écran"
# =============================================================================
#  xdotool/wmctrl peuvent échouer (pas de serveur X au bon moment, session en
#  train de fermer) — ça ne doit jamais remonter une exception jusqu'au
#  minuteur GLib qui appelle cette fonction toutes les 15 secondes.
SORTIE="$(python3 -c "
import sys, importlib.util
spec = importlib.util.spec_from_file_location('m', '$MOTEUR')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

def cherche(nom):
    return nom == 'xdotool'

def executeur(args, **kw):
    raise OSError('xdotool a disparu en cours de route')

try:
    r = m.remonte_xfdesktop(executeur=executeur, cherche=cherche)
    print('RESULT=%r' % r)
except Exception as e:
    print('EXCEPTION=%s' % e)
")"
case "$SORTIE" in
	*"RESULT=False"*)
		ok "l'outil plante -> False, encaissé proprement, aucune exception ne sort" ;;
	*"EXCEPTION"*)
		non "une exception a fui jusqu'à l'appelant — ça arrêterait le minuteur GLib : $SORTIE" ;;
	*) non "sortie inattendue : $SORTIE" ;;
esac

# =============================================================================
titre "3. Câblée au démarrage ET à une minuterie — pas juste une fois"
# =============================================================================
#  Un rechargement de xfdesktop APRÈS le lancement du fond (changement
#  d'accent, par exemple) redéfait l'ordre : un seul appel au démarrage ne
#  suffit pas. On vérifie que le fichier source appelle bien la fonction à
#  l'initialisation ET l'enregistre sur un minuteur GLib récurrent.
grep -q 'remonte_xfdesktop()' "$MOTEUR" \
	&& ok "remonte_xfdesktop() est bien appelée quelque part dans le moteur" \
	|| non "remonte_xfdesktop() n'est appelée nulle part — la fonction existe mais ne sert à rien"

grep -q 'GLib.timeout_add(ICONES_MS, self.remonte_icones)' "$MOTEUR" \
	&& ok "une minuterie GLib rappelle remonte_xfdesktop() — pas seulement au tout premier lancement" \
	|| non "pas de minuterie : un rechargement de xfdesktop plus tard referait perdre les icônes, sans retour possible"

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
