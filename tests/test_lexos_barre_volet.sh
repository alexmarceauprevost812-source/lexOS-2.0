#!/usr/bin/env bash
# =============================================================================
#  La barre : la flèche des Paramètres rapides, et la cloche qui s'en va
# =============================================================================
#  DEUX DEMANDES D'ALEX, LE MÊME JOUR, SUR LA MÊME BARRE.
#
#  1. « Changer l'image pour une flèche qui pointe vers le bas — pour les
#     paramètres rapides. » Le bouton portait icon-reglages, la roue dentée :
#     exactement la MÊME image que les Paramètres complets, deux boutons
#     voisins dans la barre et rien pour les distinguer. Une flèche vers le
#     bas dit ce que le bouton FAIT — elle tire un volet, comme sur un
#     téléphone.
#
#  2. « Notifications, on peut l'ôter de là, pis juste le garder dans les
#     Paramètres. » La cloche quitte la barre ; la section Notifications des
#     Paramètres, elle, doit rester entière — sinon on ne retire pas un
#     bouton, on supprime une fonction.
#
#  ── CE QUE CE BANC ÉPROUVE, ET POURQUOI CES CONTRÔLES-LÀ ───────────────────
#  Une icône déclarée dans un lanceur mais jamais RENDUE en image donne un
#  bouton vide — c'est très exactement le défaut qui a rongé l'icône du
#  gestionnaire de fichiers pendant des semaines : le fichier existait, mais
#  la chaîne qui mène de la source à l'écran était coupée quelque part. On
#  éprouve donc la CHAÎNE ENTIÈRE : la source existe, le crochet la rend, le
#  lanceur demande ce nom-là.
#
#  Et pour la cloche, on vérifie les DEUX bouts : qu'elle a quitté l'ordre de
#  la barre, et que ce qu'elle servait reste joignable ailleurs.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PANEL="$RACINE/config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
LANCEUR="$RACINE/config/includes.chroot/etc/skel/.config/xfce4/panel/launcher-12/lexos-volet-rapides.desktop"
HOOK="$RACINE/config/hooks/normal/0300-lexos-assets.hook.chroot"
SVG="$RACINE/branding/icon-volet-bas.svg"
APP="$RACINE/config/includes.chroot/usr/share/lexos/settings/web/app.js"
MOTEUR="$RACINE/config/includes.chroot/usr/lib/lexos/settings.py"

reussis=0; echoues=0
ok()    { printf '  \033[32m✅\033[0m %s\n' "$1"; reussis=$((reussis+1)); }
non()   { printf '  \033[31m❌\033[0m %s\n' "$1"; echoues=$((echoues+1)); }
titre() { printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

# =============================================================================
titre "1. La flèche existe VRAIMENT, de la source jusqu'au bouton"
# =============================================================================
#  MAILLON 1 : la source. Un lanceur qui demande une icône inexistante
#  n'affiche rien du tout.
if [[ -r "$SVG" ]]; then
	ok "la source du dessin est là (branding/icon-volet-bas.svg)"
else
	non "branding/icon-volet-bas.svg manque — le bouton serait vide"
fi

#  MAILLON 1 bis : c'est un vrai SVG, pas un fichier qui en porte le nom.
if python3 -c "import xml.etree.ElementTree as E,sys; E.parse(sys.argv[1])" "$SVG" 2>/dev/null; then
	ok "et c'est un SVG que le rendu saura lire"
else
	non "le SVG ne se parse pas — rsvg-convert échouerait à la construction"
fi

#  ET IL SE REND POUR DE VRAI. Un SVG peut se parser et ne rien produire
#  (formes hors cadre, syntaxe de tracé fautive). Quand le moteur de l'ISO est
#  disponible, on l'emploie ; sinon on le DIT plutôt que de faire semblant.
if command -v rsvg-convert >/dev/null 2>&1; then
	TMP="$(mktemp -u).png"
	if rsvg-convert -w 64 -h 64 -o "$TMP" "$SVG" 2>/dev/null && [[ -s "$TMP" ]]; then
		ok "rsvg-convert (le moteur de l'ISO) en produit bien une image"
	else
		non "rsvg-convert n'arrive pas à en faire une image"
	fi
	rm -f "$TMP"
else
	printf '  \033[33m•\033[0m rsvg-convert absent ici : le rendu réel n%s'"'"'a pas pu être éprouvé\n' ""
fi

#  MAILLON 2 : le crochet doit RENDRE cette icône. C'est le maillon qui avait
#  sauté pour le gestionnaire de fichiers — le fichier était là, personne ne
#  le regardait.
if grep -qE '^\s+reglages volet-bas |[[:space:]]volet-bas[[:space:]]' "$HOOK"; then
	ok "le crochet 0300 rend « volet-bas » en icône hicolor"
else
	non "« volet-bas » n'est pas dans la liste du crochet 0300 : aucune image ne serait produite"
fi

#  MAILLON 3 : le bouton de la barre demande CE nom-là. Le crochet produit
#  « lexos-<nom> » ; le lanceur doit donc dire « lexos-volet-bas ».
if grep -q '^Icon=lexos-volet-bas$' "$LANCEUR"; then
	ok "le bouton de la barre demande « lexos-volet-bas »"
else
	non "le lanceur demande autre chose : $(grep '^Icon=' "$LANCEUR" 2>/dev/null)"
fi

#  ET IL NE PORTE PLUS LA ROUE DENTÉE. C'est la demande d'Alex, mot pour mot :
#  deux boutons voisins ne doivent plus porter la même image.
if grep -q '^Icon=lexos-reglages$' "$LANCEUR"; then
	non "le bouton porte encore la roue dentée — la même image que les Paramètres"
else
	ok "il ne porte plus la roue dentée des Paramètres complets"
fi

# =============================================================================
titre "2. La cloche a quitté la barre"
# =============================================================================
#  ON LIT LE XML COMME XFCE LE LIT, pas au grep : une propriété commentée
#  ressemble beaucoup à une propriété vivante quand on cherche une chaîne.
ETAT="$(python3 - "$PANEL" <<'PY'
import sys, xml.etree.ElementTree as E
r = E.parse(sys.argv[1]).getroot()
ids, declares = [], []
for p in r.iter("property"):
    nom = p.get("name") or ""
    if nom == "plugin-ids":
        ids = [v.get("value") for v in p]
    if nom.startswith("plugin-"):
        declares.append(nom)
print("IDS:" + ",".join(ids))
print("DECLARES:" + ",".join(declares))
#  TOUT identifiant de l'ordre doit avoir sa déclaration, sinon xfce4-panel
#  affiche un trou à cette place. Retirer un greffon à moitié fait ça.
print("ORPHELINS:" + ",".join(i for i in ids if f"plugin-{i}" not in declares))
PY
)"
lire() { printf '%s' "$ETAT" | grep "^$1:" | cut -d: -f2-; }

IDS="$(lire IDS)"
if grep -q ',15,' < <(printf '%s' ",$IDS,"); then
	non "le greffon 15 (la cloche) est encore dans l'ordre de la barre"
else
	ok "la cloche ne figure plus dans l'ordre de la barre"
fi

if grep -qw 'plugin-15' < <(printf '%s' "$(lire DECLARES)"); then
	non "« plugin-15 » est encore déclaré : le greffon reviendrait"
else
	ok "« plugin-15 » n'est plus déclaré"
fi

#  LE PIÈGE DU RETRAIT À MOITIÉ : un identifiant listé sans déclaration laisse
#  un TROU dans la barre. C'est plus laid que la cloche qu'on enlevait.
ORPH="$(lire ORPHELINS)"
if [[ -z "$ORPH" ]]; then
	ok "chaque greffon de l'ordre est bien déclaré — aucun trou dans la barre"
else
	non "identifiant(s) listés sans déclaration, la barre aurait un trou : $ORPH"
fi

#  ET LA BARRE N'EST PAS VIDE : un banc qui n'a rien lu ne prouve rien.
N="$(printf '%s' "$IDS" | tr ',' '\n' | grep -c .)"
if [[ "$N" -ge 10 ]]; then
	ok "$N greffons dans la barre — le fichier a bien été lu"
else
	non "seulement $N greffons : le XML n'a pas été lu comme prévu"
fi

# =============================================================================
titre "3. …mais les notifications restent joignables dans les Paramètres"
# =============================================================================
#  RETIRER UN BOUTON N'EST PAS SUPPRIMER UNE FONCTION. Alex a dit « juste le
#  garder dans les Paramètres » : si cette section-là disparaissait un jour,
#  le retrait de la cloche deviendrait rétroactivement une perte.
if grep -q '"notifications"' "$APP"; then
	ok "la page des Paramètres porte toujours sa section Notifications"
else
	non "la section Notifications a disparu des Paramètres — la fonction serait perdue"
fi
if grep -q 'Ne pas déranger' "$APP"; then
	ok "« Ne pas déranger » y est toujours, d'un clic"
else
	non "« Ne pas déranger » a disparu"
fi
if grep -q 'xfce4-notifyd-config' "$MOTEUR"; then
	ok "les réglages fins s'ouvrent toujours (xfce4-notifyd-config)"
else
	non "plus rien n'ouvre les réglages fins des notifications"
fi
#  ET LE JOURNAL CONTINUE D'ÊTRE TENU. La cloche était ce qui le donnait à
#  lire ; le garder rempli laisse la porte ouverte à un retour en arrière.
NOTIFYD="$RACINE/config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-notifyd.xml"
if grep -q 'notification-log.*value="true"' "$NOTIFYD"; then
	ok "le journal des notifications reste tenu — rien n'est jeté"
else
	non "le journal n'est plus tenu : remettre la cloche ne ramènerait rien"
fi

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"
[[ "$echoues" -eq 0 ]]
