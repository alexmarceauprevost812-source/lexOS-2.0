#!/usr/bin/env bash
# =============================================================================
#  La taille des icônes du sélecteur de fichiers — écrite DEUX FOIS, d'accord
# =============================================================================
#  ALEX, SUR LE THINKPAD : dans « Ouvrir les fichiers », les icônes de dossier
#  font 16 px — trop petit pour distinguer d'un coup d'œil un dossier d'un
#  fichier.
#
#  ═══ POURQUOI CE N'EST PAS DU CSS ═══
#  GtkFileChooserWidget (GTK 3) calcule sa taille dans change_icon_theme() :
#      gtk_icon_size_lookup (GTK_ICON_SIZE_MENU, &width, &height);
#      priv->icon_size = MAX (width, height);
#  La liste de « Ouvrir les fichiers » n'a donc PAS de taille à elle : c'est
#  la taille « gtk-menu ». Aucune règle CSS ne peut la toucher —
#  « -gtk-icon-size » n'existe qu'en GTK 4. Le seul levier est le réglage
#  « gtk-icon-sizes ». Ce banc existe aussi pour que personne ne reperde du
#  temps à retenter la piste CSS dans lexos-theme-gen ou dans
#  prive-theme/gtk-3.0/gtk.css.
#
#  ═══ POURQUOI DEUX FICHIERS, ET CE QUE CE BANC GARDE VRAIMENT ═══
#  Sous XFCE, xfsettingsd exporte Gtk/IconSizes vers GTK et ÉCRASE
#  /etc/gtk-3.0/settings.ini pour les clés qu'il gère, une fois la session
#  ouverte. Mais settings.ini sert AVANT lui — dans l'installateur, qui
#  tourne sans session XFCE complète. D'où deux écritures :
#    · seulement settings.ini  -> bon dans l'installateur, PAS dans la session
#    · seulement xsettings.xml -> bon dans la session, PAS avant xfsettingsd
#
#  L'ASSERTION QUI COMPTE EST LA TROISIÈME : que les deux valeurs soient
#  ÉGALES. Le jour où quelqu'un n'en change qu'une, le sélecteur aura une
#  taille dans l'installateur et une autre dans la session, sans qu'aucune
#  erreur ne se lève nulle part — exactement le genre de désaccord silencieux
#  qu'aucun autre banc ne verrait.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XSET="$RACINE/config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml"
HOOK="$RACINE/config/hooks/normal/0600-lexos-theme.hook.chroot"

reussis=0; echoues=0
ok()    { printf '  \033[32m✅\033[0m %s\n' "$1"; reussis=$((reussis+1)); }
non()   { printf '  \033[31m❌\033[0m %s\n' "$1"; echoues=$((echoues+1)); }
titre() { printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

# =============================================================================
titre "1. La session : Gtk/IconSizes dans xsettings.xml"
# =============================================================================
VAL_XSET=""
if [[ -r "$XSET" ]]; then
	ok "xsettings.xml est lisible"
else
	non "xsettings.xml introuvable : $XSET"
fi

#  ON LIT L'ATTRIBUT, PAS UNE LIGNE QUI Y RESSEMBLE. Le fichier porte
#  au-dessus un commentaire XML qui explique le pourquoi et cite « gtk-menu »
#  au passage : un grep large compterait ce commentaire pour le réglage et
#  resterait vert même si la propriété disparaissait.
if [[ -r "$XSET" ]]; then
	VAL_XSET="$(sed -n 's|.*<property name="IconSizes"[^>]*value="\([^"]*\)".*|\1|p' "$XSET" | head -1)"
	if [[ -n "$VAL_XSET" ]]; then
		ok "la propriété Gtk/IconSizes est déclarée (« $VAL_XSET »)"
	else
		non "aucune propriété « IconSizes » dans xsettings.xml — la session garderait 16 px"
	fi

	if [[ "$VAL_XSET" == *"gtk-menu="* ]]; then
		ok "…et elle porte bien le jeton « gtk-menu= », celui que lit le sélecteur"
	else
		non "IconSizes ne règle pas « gtk-menu » : « $VAL_XSET » ne touche pas le sélecteur"
	fi

	#  Le bloc Gtk, et pas ailleurs : xsettings.xml porte plusieurs canaux
	#  (Net, Xft…), et une propriété rangée dans le mauvais n'atteindrait
	#  jamais GTK.
	if grep -q 'name="IconSizes"' < <(sed -n '/<property name="Gtk"/,/<\/property>/p' "$XSET"); then
		ok "…et elle est bien DANS le bloc « Gtk », pas dans un autre canal"
	else
		non "IconSizes est hors du bloc « Gtk » : xfsettingsd ne l'exporterait pas vers GTK"
	fi

	#  Le XML doit rester valide — c'est verifier.sh qui l'exige aussi, mais
	#  autant le dire ici, où l'on vient d'y ajouter une propriété.
	if python3 -c "import xml.dom.minidom,sys; xml.dom.minidom.parse('$XSET')" 2>/dev/null; then
		ok "…et le fichier se parse toujours comme du XML valide"
	else
		non "xsettings.xml ne se parse plus : XFCE ignorerait TOUT le fichier"
	fi
fi

# =============================================================================
titre "2. L'installateur : gtk-icon-sizes dans /etc/gtk-3.0/settings.ini"
# =============================================================================
VAL_HOOK=""
if [[ -r "$HOOK" ]]; then
	ok "le hook 0600 est lisible"
else
	non "hook 0600 introuvable : $HOOK"
fi

#  « sed 's/#.*$//' » D'ABORD, comme test_lexos_icones_theme.sh : le hook
#  porte au-dessus du bloc un commentaire qui explique pourquoi le réglage
#  est écrit à deux endroits, et qui cite donc « gtk-icon-sizes ». Sans ce
#  décapage, le banc compterait le commentaire pour la ligne réelle et
#  resterait vert alors que le réglage aurait disparu du heredoc.
if [[ -r "$HOOK" ]]; then
	VAL_HOOK="$(sed 's/#.*$//' "$HOOK" \
		| sed -n 's|^[[:space:]]*gtk-icon-sizes=\(.*\)$|\1|p' | head -1)"
	if [[ -n "$VAL_HOOK" ]]; then
		ok "le hook écrit gtk-icon-sizes dans settings.ini (« $VAL_HOOK »)"
	else
		non "aucun « gtk-icon-sizes » écrit par le hook — l'installateur garderait 16 px"
	fi

	if [[ "$VAL_HOOK" == *"gtk-menu="* ]]; then
		ok "…et il règle bien « gtk-menu », celui que lit le sélecteur"
	else
		non "gtk-icon-sizes ne touche pas « gtk-menu » : « $VAL_HOOK » ne changerait rien"
	fi

	#  DANS le heredoc, pas à côté : une ligne écrite après « EOF » ne
	#  partirait pas dans settings.ini.
	if grep -q '^gtk-icon-sizes=' \
		< <(sed -n '/cat > \/etc\/gtk-3.0\/settings.ini <<EOF/,/^EOF$/p' "$HOOK" | sed 's/#.*$//'); then
		ok "…et la ligne est bien DANS le bloc écrit vers settings.ini"
	else
		non "gtk-icon-sizes est hors du heredoc : rien n'atteindrait settings.ini"
	fi
fi

# =============================================================================
titre "3. LES DEUX VALEURS SONT D'ACCORD — l'assertion qui compte"
# =============================================================================
#  Rien d'autre dans le dépôt ne rapproche ces deux fichiers. Un désaccord ne
#  casserait aucune construction, ne lèverait aucune erreur, et donnerait
#  simplement deux tailles différentes selon qu'on est dans l'installateur ou
#  dans la session ouverte.
TAILLE_XSET="$(printf '%s' "$VAL_XSET" | sed -n 's|.*gtk-menu=\([0-9]*\).*|\1|p')"
TAILLE_HOOK="$(printf '%s' "$VAL_HOOK" | sed -n 's|.*gtk-menu=\([0-9]*\).*|\1|p')"

if [[ -n "$TAILLE_XSET" && -n "$TAILLE_HOOK" ]]; then
	if [[ "$TAILLE_XSET" == "$TAILLE_HOOK" ]]; then
		ok "même taille des deux côtés : ${TAILLE_XSET} px"
	else
		non "DÉSACCORD : xsettings.xml dit ${TAILLE_XSET} px, le hook dit ${TAILLE_HOOK} px — le sélecteur changerait de taille entre l'installateur et la session"
	fi

	#  La valeur complète, pas seulement le premier nombre : « 24,24 » et
	#  « 24,16 » commencent pareil et ne donnent pas la même icône.
	if [[ "$VAL_XSET" == "$VAL_HOOK" ]]; then
		ok "…et la déclaration entière est identique (« $VAL_XSET »)"
	else
		non "les déclarations diffèrent : « $VAL_XSET » contre « $VAL_HOOK »"
	fi
else
	non "impossible de comparer : taille absente d'un des deux fichiers (xsettings « $VAL_XSET », hook « $VAL_HOOK »)"
fi

# =============================================================================
titre "4. La taille demandée reste plausible"
# =============================================================================
#  UN GARDE-FOU CONTRE LA FAUTE DE FRAPPE, pas contre une décision. « 240 »
#  au lieu de « 24 » ne planterait rien : GTK demanderait des icônes énormes
#  et la liste de fichiers deviendrait inutilisable, sans le moindre message.
if [[ -n "$TAILLE_XSET" ]]; then
	if [[ "$TAILLE_XSET" =~ ^[0-9]+$ ]]; then
		ok "la taille est un entier (« $TAILLE_XSET »)"
		if (( TAILLE_XSET >= 16 && TAILLE_XSET <= 48 )); then
			ok "…et elle tient dans les bornes raisonnables (16 à 48 px)"
		else
			non "taille hors bornes : ${TAILLE_XSET} px — faute de frappe ?"
		fi
		#  Le but de la demande d'Alex : PLUS GRAND que le défaut de GTK.
		if (( TAILLE_XSET > 16 )); then
			ok "…et elle est plus grande que les 16 px par défaut, ce qui était la demande"
		else
			non "la taille vaut ${TAILLE_XSET} px : c'est le défaut, le réglage ne sert à rien"
		fi
	else
		non "la taille n'est pas un entier : « $TAILLE_XSET »"
	fi
else
	non "aucune taille à contrôler"
fi

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"
[[ "$echoues" -eq 0 ]]
