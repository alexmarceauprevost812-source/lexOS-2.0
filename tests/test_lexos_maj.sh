#!/usr/bin/env bash
# =============================================================================
#  Éprouver le suivi des mises à jour — la page sait, elle ne devine plus
# =============================================================================
#  ALEX : « fais en sorte que tout se mette à jour au fur et à mesure en
#  cliquant sur mise à jour ».
#
#  CE QUI SE PASSAIT AVANT. « Vérifier » et « Tout mettre à jour » ouvraient
#  un xfce4-terminal DÉTACHÉ (--hold -e "commande; bash") et rendaient la
#  main aussitôt : la page des Paramètres n'avait plus aucune idée de ce qui
#  se passait dans cette fenêtre — pas « en cours », pas « terminé », pas
#  « raté ». Les boutons restaient figés dans leur état de départ jusqu'à ce
#  qu'on ferme et rouvre les Paramètres à la main.
#
#  _terminal_suivi() enveloppe la commande d'un « echo $? > fichier-de-fin »
#  APRÈS elle (ce que l'utilisateur voit dans le terminal ne change pas) et
#  _maj_progres() relit ce fichier : absent -> jamais lancé, présent -> le
#  code de sortie qu'on cherche. C'est ce dict que _maj_etat() expose, et
#  que la page relit en boucle tant que « en_cours » est vrai.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS="$RACINE/config/includes.chroot/usr/lib/lexos/settings.py"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

BIN="$BANC/bin"; mkdir -p "$BIN"
ETAT="$BANC/etat"

#  Un faux xfce4-terminal qui EXÉCUTE VRAIMENT ce qu'on lui donne après
#  « -e » — un peu plus tard, pour laisser au banc le temps de constater
#  « en_cours » avant que ça se termine. C'est le seul moyen de prouver que
#  _maj_progres() lit un VRAI fichier écrit par un VRAI processus, pas une
#  intention relue dans le code.
faux_terminal() { # faux_terminal <delai-secondes>
	cat > "$BIN/xfce4-terminal" <<EOS
#!/bin/sh
cmd=""
prev=""
for a in "\$@"; do
	[ "\$prev" = "-e" ] && cmd="\$a"
	prev="\$a"
done
( sleep $1; sh -c "\$cmd" ) &
exit 0
EOS
	chmod +x "$BIN/xfce4-terminal"
}

appelle() { # appelle <fonction-python-a-evaluer>
	PATH="$BIN:/usr/bin:/bin" LEXOS_MAJ_ETAT_DIR="$ETAT" python3 -c "
import sys, importlib.util
spec = importlib.util.spec_from_file_location('s', '$SETTINGS')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
$1
"
}

attend_fin() { # attend_fin <cle> <secondes-max> — sondage réel, pas un sleep fixe
	local cle="$1" max="$2" tours=0
	while [ "$tours" -lt "$((max * 5))" ]; do
		R="$(appelle "print(m._maj_progres('$cle'))")"
		case "$R" in *"'en_cours': False"*) return 0 ;; esac
		sleep 0.2
		tours=$((tours + 1))
	done
	return 1
}

# =============================================================================
titre "1. Jamais lancé -> None, pas un faux « en cours »"
# =============================================================================
rm -rf "$ETAT"
R="$(appelle "print(m._maj_progres('verifier'))")"
[ "$R" = "None" ] \
	&& ok "aucun clic encore -> _maj_progres() rend None, pas un état inventé" \
	|| non "sans avoir jamais lancé « verifier », la réponse est « $R »"

# =============================================================================
titre "2. act_maj('verifier') EN VRAI — en cours, puis fini avec succès"
# =============================================================================
#  « lexos doctor » (la vraie commande d'act_maj('verifier')) n'existe pas
#  dans ce bac à sable — un faux « lexos » qui répond 0 à tout, pour éprouver
#  le CHEMIN RÉUSSI sans dépendre d'un outil absent du banc.
rm -rf "$ETAT"; mkdir -p "$BANC/bin"
cat > "$BIN/lexos" <<'EOS'
#!/bin/sh
exit 0
EOS
chmod +x "$BIN/lexos"
faux_terminal 1
R="$(appelle "print(m.act_maj('verifier'))")"
case "$R" in
	*"'ok': True"*) ok "act_maj('verifier') répond ok tout de suite (le terminal est détaché)" ;;
	*) non "act_maj('verifier') a répondu « $R »" ;;
esac

#  TOUT DE SUITE APRÈS : le faux terminal dort encore une seconde, donc
#  « en_cours » DOIT être vrai. Un test qui sauterait cette vérification
#  pourrait passer même si _terminal_suivi() ne posait jamais le fichier de
#  début — 0 preuve que le suivi couvre bien le cas « ça tourne ».
R="$(appelle "print(m._maj_progres('verifier'))")"
case "$R" in
	*"'en_cours': True"*) ok "juste après le clic, la page verrait « en cours » — pas figée dans le vide" ;;
	*) non "immédiatement après le lancement : « $R » (devrait être en_cours=True)" ;;
esac

attend_fin verifier 5 \
	&& ok "le faux terminal a fini (~1s) : _maj_progres() bascule bien à en_cours=False" \
	|| non "toujours « en cours » 5 secondes après la fin réelle du processus"

R="$(appelle "print(m._maj_progres('verifier'))")"
case "$R" in
	*"'ok': True"*) ok "commande réussie (code 0) -> ok=True" ;;
	*) non "après succès, _maj_progres() dit « $R »" ;;
esac

# =============================================================================
titre "3. Une commande qui échoue -> ok=False, pas un succès inventé"
# =============================================================================
rm -rf "$ETAT"; mkdir -p "$BANC/bin"
faux_terminal 0
#  On ne peut pas passer une commande qui échoue par act_maj() (la liste des
#  gestes est fermée) — on appelle donc _terminal_suivi() directement, ce
#  qu'act_maj() fait en interne pour de vrai.
appelle "m._terminal_suivi('t', 'false', 'tout')" >/dev/null
attend_fin tout 5 || non "le faux terminal (délai nul) n'a jamais fini"
R="$(appelle "print(m._maj_progres('tout'))")"
case "$R" in
	*"'ok': False"*) ok "commande en échec (code 1, « false ») -> ok=False" ;;
	*"'ok': True"*)  non "« false » a échoué mais _maj_progres() dit ok=True" ;;
	*) non "sortie inattendue : $R" ;;
esac

# =============================================================================
titre "4. _maj_etat() expose les trois gestes, sans jamais planter"
# =============================================================================
rm -rf "$ETAT"
R="$(appelle "print(sorted(m._maj_etat()['progres'].keys()))")"
[ "$R" = "['firmware', 'tout', 'verifier']" ] \
	&& ok "_maj_etat()['progres'] porte bien les trois clés (verifier/tout/firmware)" \
	|| non "clés inattendues dans progres : $R"

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
