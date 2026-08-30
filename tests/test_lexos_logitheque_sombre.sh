#!/usr/bin/env bash
# =============================================================================
#  La Logithèque doit être SOMBRE — sinon son écriture blanche est invisible
# =============================================================================
#  ALEX, TROIS PHOTOS : « ensuite la Logithèque, regarde, on voit pas les
#  écritures. » Les cartes des applications sont des rectangles BLANCS, un
#  carré gris au milieu, et aucun nom lisible. Le nom est là : écrit en blanc,
#  sur blanc.
#
#  ═══ LA CAUSE, ET C'EST libadwaita QUI LA DIT ═══
#  Relevé mot pour mot dans son binaire :
#
#      « Using GtkSettings:gtk-application-prefer-dark-theme with libadwaita
#        is unsupported. Please use AdwStyleManager:color-scheme instead. »
#
#  Tout le mode sombre de LexOS passe par CE réglage-là. La Logithèque
#  (gnome-software, GTK 4 + libadwaita) l'ignore donc EXPLICITEMENT et rend en
#  clair, pendant que notre feuille de style force le texte en blanc.
#
#  Ce que libadwaita écoute vraiment, relevé dans le même binaire :
#  « org.gnome.desktop.interface », clé « color-scheme » — valeurs
#  « default | prefer-dark | prefer-light », confirmées dans le schéma livré
#  par gsettings-desktop-schemas.
#
#  ═══ LE MAILLON QUI MANQUAIT, ET QUE CE BANC SURVEILLE ═══
#  Poser le fichier de surcharge ne suffit PAS : une surcharge n'agit
#  qu'une fois compilée dans gschemas.compiled. Les paquets le font par un
#  déclencheur dpkg — mais ils s'installent AVANT que includes.chroot ne
#  dépose notre fichier. Sans un appel explicite à glib-compile-schemas dans
#  un crochet, le correctif serait parti dans l'ISO sans le moindre effet.
#  C'est le défaut le plus répété de ce dépôt : le correctif à moitié.
#
#  ═══ CE QUE CE BANC ÉPROUVE VRAIMENT ═══
#  Pas « le fichier existe-t-il » — il existait déjà quand rien ne marchait.
#  Il fait le VRAI aller-retour : il compile notre surcharge avec le VRAI
#  glib-compile-schemas et RELIT la valeur avec gsettings. Puis il retire la
#  surcharge et recompile, pour prouver qu'il sait voir la différence.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SURCHARGE="$RACINE/config/includes.chroot/usr/share/glib-2.0/schemas/90-lexos-sombre.gschema.override"
HOOK="$RACINE/config/hooks/normal/0600-lexos-theme.hook.chroot"
GEN="$RACINE/config/includes.chroot/usr/bin/lexos-theme-gen"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

reussis=0; echoues=0
ok()    { printf '  \033[32m✅\033[0m %s\n' "$1"; reussis=$((reussis+1)); }
non()   { printf '  \033[31m❌\033[0m %s\n' "$1"; echoues=$((echoues+1)); }
titre() { printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

# =============================================================================
titre "1. La surcharge existe et dit exactement ce qu'il faut"
# =============================================================================
if [[ -r "$SURCHARGE" ]]; then
	ok "90-lexos-sombre.gschema.override est livré"
else
	non "aucune surcharge : la Logithèque resterait en clair, texte blanc sur blanc"
	printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"; exit 1
fi

#  On le lit comme GLib le lit — un fichier de clés — et pas au grep : un
#  fichier qu'un lecteur de configuration refuse est un fichier que
#  glib-compile-schemas refuse aussi, et un grep content de trouver sa ligne
#  ne le dirait jamais.
LU="$(python3 - "$SURCHARGE" <<'PY'
import configparser, sys
c = configparser.ConfigParser()
try:
    c.read(sys.argv[1], encoding="utf-8")
except Exception as e:
    print("ERREUR:" + str(e)); raise SystemExit
sec = "org.gnome.desktop.interface"
print("SECTIONS:" + ",".join(c.sections()))
print("VALEUR:" + (c[sec].get("color-scheme", "") if sec in c else ""))
PY
)"
lire() { printf '%s' "$LU" | sed -n "s/^$1://p"; }

if printf '%s' "$LU" | grep -q '^ERREUR:'; then
	non "le fichier ne se parse pas : $(lire ERREUR)"
elif printf '%s' "$(lire SECTIONS)" | grep -q 'org\.gnome\.desktop\.interface'; then
	ok "il vise « org.gnome.desktop.interface » — le schéma que libadwaita lit"
else
	non "mauvaise section : « $(lire SECTIONS) » — libadwaita ne lirait rien"
fi

VALEUR="$(lire VALEUR)"
if [[ "$VALEUR" == "'prefer-dark'" ]]; then
	ok "color-scheme = 'prefer-dark' — les guillemets simples que GVariant exige"
else
	non "color-scheme vaut « $VALEUR » : attendu 'prefer-dark', guillemets simples compris"
fi

#  ET LA VALEUR DOIT ÊTRE UNE DE CELLES QUE LE SCHÉMA ACCEPTE. Une faute de
#  frappe (« prefer_dark », « dark ») ne ferait PAS échouer la compilation :
#  elle donnerait juste une clé refusée en silence.
#  LE PIÈGE, TROUVÉ EN ÉCRIVANT CE BANC : « color-scheme » n'est pas une
#  chaîne libre, c'est une ÉNUMÉRATION — et la liste des valeurs permises ne
#  vit PAS dans le schéma, elle vit dans un second fichier
#  (org.gnome.desktop.enums.xml, énumération « GDesktopColorScheme »). Le
#  premier jet de ce banc cherchait au mauvais endroit et accusait une valeur
#  parfaitement valide d'être inventée.
SCHEMA_XML="/usr/share/glib-2.0/schemas/org.gnome.desktop.interface.gschema.xml"
ENUMS_XML="/usr/share/glib-2.0/schemas/org.gnome.desktop.enums.xml"
if [[ -r "$SCHEMA_XML" && -r "$ENUMS_XML" ]]; then
	if grep -q "name=\"color-scheme\" enum=\"org.gnome.desktop.GDesktopColorScheme\"" "$SCHEMA_XML"; then
		ok "la clé « color-scheme » existe bien, et c'est une énumération"
	else
		non "« color-scheme » introuvable dans le schéma installé — clé inventée ?"
	fi
	if grep -q "nick=\"prefer-dark\"" "$ENUMS_XML"; then
		ok "« prefer-dark » figure dans l'énumération livrée par gsettings-desktop-schemas"
	else
		non "« prefer-dark » n'est pas une valeur permise : la surcharge serait rejetée"
	fi
else
	non "gsettings-desktop-schemas absent de cette machine : la valeur n'a pas pu être confrontée au schéma"
fi

# =============================================================================
titre "2. LE VRAI ALLER-RETOUR : compiler, puis relire"
# =============================================================================
#  LE CŒUR DU BANC. Tout le reste est de la lecture de fichier ; ici on fait
#  faire le travail aux VRAIS outils, ceux que la construction emploiera.
if ! command -v glib-compile-schemas >/dev/null 2>&1; then
	non "glib-compile-schemas absent : l'aller-retour n'a pas pu être fait (installer libglib2.0-bin)"
elif [[ ! -r "$SCHEMA_XML" || ! -r "$ENUMS_XML" ]]; then
	non "gsettings-desktop-schemas manque : l'aller-retour n'a pas pu être fait"
else
	D="$BANC/schemas"
	mkdir -p "$D"
	#  LES DEUX FICHIERS. Sans l'énumération, glib-compile-schemas refuse le
	#  schéma, aucun gschemas.compiled n'est écrit, et gsettings retombe sur
	#  celui du système : le banc lisait « default » et croyait la surcharge
	#  cassée. L'outil avait raison, c'est le banc qui était mal monté.
	cp "$SCHEMA_XML" "$ENUMS_XML" "$D/"
	cp "$SURCHARGE" "$D/"
	if glib-compile-schemas "$D" 2>"$BANC/compil.txt"; then
		ok "glib-compile-schemas accepte notre surcharge (aucune erreur)"
	else
		non "glib-compile-schemas REFUSE notre surcharge : $(head -2 "$BANC/compil.txt" | tr '\n' ' ')"
	fi
	AVEC="$(GSETTINGS_SCHEMA_DIR="$D" gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null)"
	if [[ "$AVEC" == "'prefer-dark'" ]]; then
		ok "relu après compilation : $AVEC — la Logithèque s'ouvrira en sombre"
	else
		non "relu après compilation : « $AVEC » au lieu de 'prefer-dark' — la surcharge n'a pas pris"
	fi

	#  ═══ LA MUTATION ═══ On retire la surcharge et on recompile. Si la
	#  valeur ne CHANGE pas, c'est que le contrôle ci-dessus lisait le défaut
	#  du schéma et aurait été vert même sans notre fichier — un banc qui ne
	#  prouve rien. C'est arrivé assez souvent dans ce dépôt pour qu'on le
	#  vérifie à chaque fois.
	rm -f "$D/90-lexos-sombre.gschema.override" "$D/gschemas.compiled"
	glib-compile-schemas "$D" 2>/dev/null
	SANS="$(GSETTINGS_SCHEMA_DIR="$D" gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null)"
	if [[ "$SANS" != "$AVEC" ]]; then
		ok "sans la surcharge la valeur retombe à $SANS — le contrôle voit bien la différence"
	else
		non "même valeur ($SANS) avec et sans la surcharge : ce banc ne prouverait rien"
	fi
fi

# =============================================================================
titre "3. Quelqu'un compile-t-il ? — le maillon qui manquait"
# =============================================================================
#  Le fichier posé sans cet appel, c'est un correctif livré et inerte.
if grep -q 'glib-compile-schemas' "$HOOK"; then
	ok "le crochet 0600 appelle glib-compile-schemas"
else
	non "AUCUN crochet ne compile les schémas : la surcharge partirait dans l'ISO sans effet"
fi
if grep -q 'glib-compile-schemas "\$SCHEMAS_DIR"\|glib-compile-schemas /usr/share/glib-2.0/schemas' "$HOOK"; then
	ok "il compile bien /usr/share/glib-2.0/schemas, là où notre fichier atterrit"
else
	non "il compile un autre dossier que celui où includes.chroot dépose la surcharge"
fi
#  Et il ne doit pas pouvoir ARRÊTER la construction : le crochet tourne sous
#  « set -e », et une Logithèque non installée n'est pas une panne.
if grep -q 'command -v glib-compile-schemas' "$HOOK"; then
	ok "l'appel est gardé — une machine sans l'outil ne casse pas la construction"
else
	non "appel non gardé sous « set -e » : un outil absent ferait échouer toute l'ISO"
fi

# =============================================================================
titre "4. L'outil qui compile part VRAIMENT dans l'ISO"
# =============================================================================
#  Il arrivait par ricochet (packagekit en dépend), donc par une liste
#  OPTIONNELLE, donc « au mieux ». Un correctif ne dépend pas du temps qu'il
#  fait sur les miroirs.
if grep -qx 'libglib2.0-bin' "$RACINE"/config/package-lists/*.list.chroot; then
	ok "libglib2.0-bin est dans une liste OBLIGATOIRE — glib-compile-schemas sera là"
else
	non "libglib2.0-bin n'est dans aucune liste obligatoire : la compilation pourrait ne jamais avoir lieu"
fi

# =============================================================================
titre "5. Le mode COURANT suit — « lexos theme clair » aussi"
# =============================================================================
#  La surcharge ne pose qu'un DÉFAUT. Sans ce second morceau, passer au thème
#  de jour donnerait un bureau clair et une Logithèque restée sombre : le même
#  désaccord, dans l'autre sens.
#
#  On ne lit pas le script : on le LANCE, avec un faux gsettings sur le PATH
#  qui note ce qu'on lui demande.
essai_mode() { # essai_mode <mode|""> <attendu|"rien"> <avec-bus 0/1>
	local mode="$1" attendu="$2" bus="$3"
	#  Sur une ligne séparée : dans un seul « local a=… b=$a », bash développe
	#  TOUS les mots avant d'affecter quoi que ce soit — $bus y serait encore
	#  vide, et « set -u » le dit sans ménagement.
	local d="$BANC/gen-${mode:-defaut}-$bus"
	mkdir -p "$d/home" "$d/bin"
	cat > "$d/bin/gsettings" <<'X'
#!/bin/sh
echo "$*" >> "$GS_LOG"
X
	chmod +x "$d/bin/gsettings"
	local args=(orange)
	[[ -n "$mode" ]] && args+=(--mode "$mode")
	if [[ "$bus" == "1" ]]; then
		GS_LOG="$d/appels.txt" PATH="$d/bin:$PATH" HOME="$d/home" \
			DBUS_SESSION_BUS_ADDRESS="unix:path=/faux-pour-le-banc" \
			bash "$GEN" "${args[@]}" >/dev/null 2>&1
	else
		GS_LOG="$d/appels.txt" PATH="$d/bin:$PATH" HOME="$d/home" \
			env -u DBUS_SESSION_BUS_ADDRESS \
			bash "$GEN" "${args[@]}" >/dev/null 2>&1
	fi
	local vu; vu="$(cat "$d/appels.txt" 2>/dev/null || true)"
	if [[ "$attendu" == "rien" ]]; then
		if [[ -z "$vu" ]]; then
			ok "sans bus de session : aucun appel — le chroot de construction ne criera pas"
		else
			non "sans bus de session il appelle quand même gsettings : « $vu »"
		fi
	elif printf '%s' "$vu" | grep -q "set org.gnome.desktop.interface color-scheme $attendu"; then
		ok "mode « ${mode:-sombre} » → color-scheme $attendu"
	else
		non "mode « ${mode:-sombre} » : attendu « $attendu », vu « ${vu:-aucun appel} »"
	fi
}
if [[ -r "$GEN" ]]; then
	essai_mode ""       prefer-dark  1
	essai_mode "clair"  prefer-light 1
	essai_mode ""       rien         0
else
	non "lexos-theme-gen introuvable — le mode courant n'a pas pu être éprouvé"
fi

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"
[[ "$echoues" -eq 0 ]]
