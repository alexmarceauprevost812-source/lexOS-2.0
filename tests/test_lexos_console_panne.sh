#!/usr/bin/env bash
# =============================================================================
#  LA CONSOLE DOIT DIRE POURQUOI LE BUREAU N'A PAS DÉMARRÉ
# =============================================================================
#  CE QU'ALEX A VU. Alienware Aurora ACT1250, RTX 5060, entrée normale du
#  menu : le bureau ne démarre pas, la machine retombe en console — et la
#  console affiche la bannière lexfetch. Un masque en blocs, des couleurs,
#  des chiffres qui ont l'air d'aller. Rien ne disait que quelque chose avait
#  échoué ; il ne savait même pas s'il était au bon endroit.
#
#  ═══ LES DEUX FAUTES QUE CE BANC ÉPROUVE, ET ELLES SONT SYMÉTRIQUES ═══
#
#  1. NE RIEN DIRE quand la session graphique a échoué. C'est le défaut du
#     jour : on arrive sur un écran joyeux au lieu d'une explication.
#  2. CRIER AU LOUP quand tout va bien. Un Ctrl+Alt+F2 pendant que le bureau
#     tourne, une session SSH, une machine volontairement en mode serveur :
#     annoncer une panne à quelqu'un dont la machine marche, c'est le bogue
#     du dock à l'envers — affirmer sans avoir mesuré.
#
#  La deuxième coûte aussi cher que la première, et c'est pour ça qu'il y a
#  QUATRE conditions dans session_graphique_absente() et quatre contrôles ici.
#
#  ═══ ET L'AVERTISSEMENT QUI NE SE SÉPARE PAS DU REMÈDE ═══
#  Le message dit, le cas échéant, de couper le Secure Boot. Sur une machine
#  en double démarrage, ce conseil-là est dangereux à moitié : BitLocker
#  réclamera sa clé de récupération au prochain démarrage de Windows, et
#  plusieurs jeux exigent le Secure Boot actif. Alex a Windows 11 à côté, et
#  il s'en sert pour jouer. Le banc refuse donc un message qui dirait
#  « Disabled » sans ces deux mots-là.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_DIR="$RACINE/config/includes.chroot/usr/share/lexos/shell"
SG="$SHELL_DIR/session-graphique.sh"
SB="$SHELL_DIR/secure-boot.sh"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0; MUETS=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
muet() { printf '  \033[33m•\033[0m %s\n' "$1"; MUETS=$((MUETS+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

for F in "$SG" "$SB"; do
	[ -r "$F" ] || { non "fichier manquant : $F"; printf '\n'; exit 1; }
done

# ===========================================================================
titre "1. LES DEUX FRAGMENTS RESTENT EN POSIX PUR"
# ===========================================================================
#  lexos-tv est en #!/bin/sh. Un « [[ ]] » glissé ici ferait disparaître la
#  fonction EN SILENCE, et l'appelant conclurait « pas de panne ».
for F in "$SG" "$SB"; do
	if sh -n "$F" 2>/dev/null; then
		ok "$(basename "$F") s'analyse en /bin/sh"
	else
		non "$(basename "$F") n'est plus du shell POSIX : lexos-tv ne pourra plus le sourcer"
	fi
	SALE="$(grep -vE '^\s*#' "$F" | grep -cE '\[\[|\]\]|local |declare |=\(' || true)"
	[ "${SALE:-0}" = "0" ] \
		&& ok "…et n'utilise aucune tournure propre à bash" \
		|| non "$(basename "$F") contient $SALE tournure(s) bash : elles casseront dans lexos-tv"
done

# ===========================================================================
titre "2. ON NE CRIE PAS AU LOUP — quatre façons de ne PAS être en panne"
# ===========================================================================
#  Chaque cas est joué pour de vrai, en sourçant le fragment avec un
#  environnement fabriqué. On ne relit pas les conditions : on les exerce.
mkdir -p "$BANC/x11" "$BANC/modules-vides"
: > "$BANC/modules"                       # aucun module chargé
printf 'nvidia 1 - Live 0x0\n' > "$BANC/modules-nvidia"

absente() {   # absente <extra-env…> : rend « oui » ou « non »
	env -i PATH="$PATH" HOME="$BANC" \
		LEXOS_MODULES="$BANC/modules" \
		LEXOS_X11_SOCKETS="$BANC/x11" \
		LEXOS_BUILD_CONF="$BANC/build.conf" \
		LEXOS_SHELL_DIR="$SHELL_DIR" \
		LEXOS_CIBLE_DEFAUT="graphical.target" \
		"$@" \
		sh -c '. "$0"; if session_graphique_absente; then echo oui; else echo non; fi' "$SG"
}

[ "$(absente)" = "oui" ] \
	&& ok "console sans bureau, machine graphique : c'est une PANNE, on le dit" \
	|| non "le cas d'Alex n'est pas reconnu comme une panne : le message ne s'affichera jamais"

[ "$(absente DISPLAY=:0)" = "non" ] \
	&& ok "un shell qui a DISPLAY : rien (il EST dans le bureau)" \
	|| non "on annoncerait une panne à un terminal du bureau"

[ "$(absente SSH_CONNECTION='10.0.0.1 22 10.0.0.2 22')" = "non" ] \
	&& ok "une session SSH : rien (elle n'a jamais de bureau)" \
	|| non "on annoncerait une panne à chaque connexion SSH"

touch "$BANC/x11/X0"
[ "$(absente)" = "non" ] \
	&& ok "un serveur d'affichage tourne (Ctrl+Alt+F2) : rien" \
	|| non "on annoncerait une panne à quelqu'un qui a juste changé de console"
rm -f "$BANC/x11/X0"

[ "$(absente LEXOS_CIBLE_DEFAUT=multi-user.target)" = "non" ] \
	&& ok "machine volontairement en mode serveur : rien" \
	|| non "on annoncerait une panne sur une machine sans bureau voulu"

# ===========================================================================
titre "3. LE MESSAGE DIT LA CAUSE, ET IL LA MESURE"
# ===========================================================================
dire() {   # dire <extra-env…>
	env -i PATH="$PATH" HOME="$BANC" \
		LEXOS_MODULES="$BANC/modules" \
		LEXOS_X11_SOCKETS="$BANC/x11" \
		LEXOS_BUILD_CONF="$BANC/build.conf" \
		LEXOS_SHELL_DIR="$SHELL_DIR" \
		LEXOS_EFIVARS="$BANC/efivars-off" \
		"$@" \
		sh -c '. "$0"; session_graphique_dire' "$SG"
}
mkdir -p "$BANC/efivars-off" "$BANC/efivars-on"
python3 - "$BANC/efivars-on/SecureBoot-8be4df61" <<'PY' 2>/dev/null || muet "python3 absent : le cas Secure Boot ne sera pas joué"
import sys
#  5 octets : 4 d'attributs, puis la valeur. Le cinquième vaut 1 = ACTIF.
open(sys.argv[1], "wb").write(bytes([6, 0, 0, 0, 1]))
PY

VU="$(dire)"
case "$VU" in
	*"LE BUREAU N'A PAS DÉMARRÉ"*) ok "le message dit d'abord CE QUI n'a pas démarré" ;;
	*) non "le message ne dit pas ce qui a échoué : $(printf '%s' "$VU" | head -1)" ;;
esac
case "$VU" in
	*"AUCUN pilote d'affichage n'est chargé"*) ok "…puis la cause MESURÉE : aucun pilote chargé" ;;
	*) non "le message ne nomme pas la cause mesurée" ;;
esac
case "$VU" in
	*"sudo lexos tv"*) ok "…et la commande pour en savoir plus" ;;
	*) non "le message n'indique pas « sudo lexos tv »" ;;
esac

#  Un pilote chargé : la cause est ailleurs, et le message doit le DIRE au
#  lieu d'accuser le pilote par habitude.
VU_PILOTE="$(dire LEXOS_MODULES="$BANC/modules-nvidia")"
case "$VU_PILOTE" in
	*"un pilote d'affichage EST chargé"*) ok "avec un pilote chargé, le message n'accuse pas le pilote" ;;
	*"AUCUN pilote"*) non "le message dit « aucun pilote » alors que nvidia EST chargé — il ne mesure rien" ;;
	*) non "le cas « pilote chargé » ne donne rien de reconnaissable" ;;
esac

#  Une ISO livrée SANS pilote : c'est écrit dans build.conf, pas déduit.
printf 'LEXOS_NVIDIA_ETAT="absent"\n' > "$BANC/build.conf"
VU_ABSENT="$(dire)"
case "$VU_ABSENT" in
	*"N'EMBARQUE AUCUN PILOTE NVIDIA"*) ok "une ISO sans pilote le dit, au lieu de laisser chercher le BIOS" ;;
	*) non "une ISO sans pilote ne se distingue pas d'un Secure Boot actif" ;;
esac
rm -f "$BANC/build.conf"

# ===========================================================================
titre "4. SECURE BOOT : LE REMÈDE NE PART JAMAIS SANS SES DEUX AVERTISSEMENTS"
# ===========================================================================
#  ═══ POURQUOI C'EST LE CONTRÔLE LE PLUS IMPORTANT DE CE FICHIER ═══
#  « Boot -> Secure Boot -> Disabled » sur une machine en double démarrage,
#  c'est un conseil qui peut coûter l'accès à Windows. Les deux conséquences
#  sont connues et aucune ne se devine :
#    · BitLocker réclame sa CLÉ DE RÉCUPÉRATION au démarrage suivant ;
#    · plusieurs jeux exigent le Secure Boot actif et refusent de se lancer.
#  Le contrôle ne cherche donc pas « le message parle de BitLocker quelque
#  part » : il exige que DÈS QUE le mot « Disabled » apparaît, les deux
#  avertissements soient là aussi.
SB_ACTIF="$(env -i PATH="$PATH" LEXOS_EFIVARS="$BANC/efivars-on" \
	sh -c '. "$0"; secure_boot_dire' "$SB" 2>&1)"
SB_INACTIF="$(env -i PATH="$PATH" LEXOS_EFIVARS="$BANC/efivars-off" \
	sh -c '. "$0"; secure_boot_dire' "$SB" 2>&1)"

case "$SB_ACTIF" in
	*"SECURE BOOT : ACTIF"*) ok "Secure Boot actif : détecté sur la vraie variable EFI (5e octet)" ;;
	*) muet "le cas « Secure Boot actif » n'a pas pu être joué : $(printf '%s' "$SB_ACTIF" | head -1)" ;;
esac
case "$SB_INACTIF" in
	*"inactif"*) ok "…et absent de la variable = inactif, sans accuser personne" ;;
	*) non "sans variable EFI, le message n'annonce pas « inactif » : $(printf '%s' "$SB_INACTIF" | head -1)" ;;
esac

#  LA RÈGLE, ÉPROUVÉE SUR LE TEXTE RENDU.
if ! printf '%s' "$SB_ACTIF" | grep -q 'Disabled'; then
	muet "le message ne propose pas de couper le Secure Boot : les avertissements ne s'appliquent pas"
else
	printf '%s' "$SB_ACTIF" | grep -qE 'BitLocker|BITLOCKER' \
		&& ok "le remède est accompagné de l'avertissement BitLocker" \
		|| non "le message dit « Disabled » SANS parler de BitLocker : Windows peut devenir inaccessible"
	#  ⚠ PAS DE « grep -i » SUR UN ACCENT. Le banc tourne sous « env -i »,
	#  donc en locale C : grep -i n'y sait pas replier É sur é, et le contrôle
	#  rougissait sur un message qui dit pourtant « CLÉ DE RÉCUPÉRATION » en
	#  toutes lettres. Un faux rouge coûte exactement ce que coûte un faux
	#  vert : on nomme donc les deux casses.
	printf '%s' "$SB_ACTIF" | grep -qE 'récupération|RÉCUPÉRATION' \
		&& ok "…et nomme la CLÉ DE RÉCUPÉRATION, qu'il faut avoir AVANT" \
		|| non "BitLocker est nommé mais pas sa clé de récupération : l'avertissement ne sert à rien"
	printf '%s' "$SB_ACTIF" | grep -qE 'anti-triche|ANTI-TRICHE' \
		&& ok "…et l'avertissement anti-triche (Alex joue sous Windows)" \
		|| non "le message dit « Disabled » SANS avertir que des jeux exigent le Secure Boot"
fi

#  Et dans le message de panne complet, qui l'inclut par référence.
VU_SB="$(dire LEXOS_EFIVARS="$BANC/efivars-on")"
if printf '%s' "$VU_SB" | grep -q 'Disabled'; then
	printf '%s' "$VU_SB" | grep -qE 'BitLocker|BITLOCKER' && printf '%s' "$VU_SB" | grep -qE 'anti-triche|ANTI-TRICHE' \
		&& ok "le message de la console hérite des deux avertissements (un seul texte, pas deux)" \
		|| non "le message de la console propose « Disabled » sans les avertissements : il a recopié au lieu de réutiliser"
else
	non "Secure Boot actif + aucun pilote chargé : le message n'en parle même pas"
fi

# ===========================================================================
titre "5. ON NE PROMET PAS UNE COMMANDE QUI N'EXISTE PAS"
# ===========================================================================
#  La voie propre (signer le pilote) arrive par étapes. Tant que l'outil
#  n'est pas installé, l'envoyer taper une commande introuvable devant une
#  console sans bureau serait la pire des réponses.
if printf '%s' "$SB_ACTIF" | grep -q 'lexos-signer-pilote'; then
	non "le message propose « lexos-signer-pilote » alors que la commande n'est pas dans le PATH du banc"
else
	ok "aucune commande introuvable n'est proposée"
fi

# ===========================================================================
titre "6. ET C'EST RÉELLEMENT BRANCHÉ, AVANT LA BANNIÈRE"
# ===========================================================================
#  ═══ LE CONTRÔLE SANS LEQUEL TOUT LE RESTE EST DÉCORATIF ═══
#  Un fragment parfait que personne n'appelle ne s'affiche jamais. Et
#  l'ORDRE compte autant que l'appel : la panne doit se lire AVANT le masque
#  en blocs, pas sous lui — c'est précisément parce que la bannière arrivait
#  seule qu'Alex n'a pas su qu'il était en panne.
INTER="$RACINE/config/includes.chroot/usr/share/lexos/shell/interactive.sh"
if [[ ! -r "$INTER" ]]; then
	non "interactive.sh introuvable ($INTER)"
else
	L_PANNE="$(grep -n 'session_graphique_dire' "$INTER" | head -1 | cut -d: -f1)"
	L_BANNIERE="$(grep -n '^\s*lexfetch\s*$' "$INTER" | head -1 | cut -d: -f1)"
	if [ -z "$L_PANNE" ]; then
		non "interactive.sh n'appelle jamais session_graphique_dire : le message ne s'affichera nulle part"
	elif [ -z "$L_BANNIERE" ]; then
		muet "la bannière n'a pas été trouvée dans interactive.sh : l'ordre n'a pas pu être vérifié"
	elif [ "$L_PANNE" -lt "$L_BANNIERE" ]; then
		ok "la panne se lit AVANT la bannière lexfetch (lignes $L_PANNE puis $L_BANNIERE)"
	else
		non "la panne s'afficherait APRÈS le masque en blocs : c'est le défaut d'origine"
	fi
	#  ⚠ ON RETIRE LES COMMENTAIRES AVANT DE CHERCHER, ET C'EST MESURÉ.
	#  Ce contrôle cherchait « session_graphique_absente » dans TOUT
	#  interactive.sh — or la ligne 286 de ce fichier est un COMMENTAIRE qui
	#  nomme la fonction (« ⚠ ON NE CRIE PAS AU LOUP.
	#  session_graphique_absente() exige QUATRE… »). Mutation jouée : on retire
	#  le « if session_graphique_absente; then … fi » et on laisse le
	#  commentaire — le banc restait à 23/23 VERTS, et chaque connexion SSH,
	#  chaque Ctrl+Alt+F2 aurait annoncé une panne. C'est la faute n°1 de la
	#  consigne, certifiée verte par le seul point du dépôt qui gardait cette
	#  garde-là. Troisième fois que ce dépôt paie « le contrôle qui lit la
	#  prose » ; il faudra finir par en faire une règle.
	GARDE="$(grep -v '^[[:space:]]*#' "$INTER" | grep -c 'session_graphique_absente' || true)"
	[ "${GARDE:-0}" != "0" ] \
		&& ok "…et seulement quand les quatre conditions sont réunies" \
		|| non "interactive.sh affiche le message sans vérifier qu'il y a vraiment une panne : chaque SSH et chaque Ctrl+Alt+F2 annoncerait une panne"
fi

# ===========================================================================
titre "7. « JE N'AI PAS PU LIRE » N'EST PAS UNE MESURE"
# ===========================================================================
#  ═══ LE BOGUE DU DOCK, DANS LE FICHIER QUI LE RACONTE ═══
#  Deux gardes concluaient quand elles n'avaient rien pu lire, et dans le sens
#  qui CRIE AU LOUP :
#    · session_graphique_attendue() rendait « le graphique est attendu » —
#      donc feu vert pour annoncer la panne — quand systemctl était absent ou
#      muet. Son propre commentaire disait « on ne conclut pas » ; la valeur
#      de retour, elle, concluait.
#    · session_graphique_pilote() rendait la même chose pour « aucun pilote
#      chargé » et pour « /proc/modules illisible », et l'appelant imprimait
#      alors le mot « Mesuré » sur ce qu'il n'avait pas lu.
#  secure-boot.sh, deux fichiers plus loin, fait pourtant la distinction :
#  « Mode du disque : impossible à vérifier » n'est pas « rien d'anormal ».
#  On fabrique un PATH qui contient tout sauf systemctl, et un systemctl
#  MUET : la couture LEXOS_CIBLE_DEFAUT ne suffit pas ici, puisque c'est
#  justement le chemin « pas de couture » qu'on veut exercer.
mkdir -p "$BANC/outils"
for B in sh grep awk sed od tail head cat printf; do
	CHEMIN="$(command -v "$B" 2>/dev/null || true)"
	[ -n "$CHEMIN" ] && ln -sf "$CHEMIN" "$BANC/outils/$B"
done
cat > "$BANC/outils-muet-systemctl" <<'EOF'
#!/bin/sh
exit 0
EOF
mkdir -p "$BANC/outils-muet"
cp -a "$BANC/outils/." "$BANC/outils-muet/" 2>/dev/null || true
install -m 0755 "$BANC/outils-muet-systemctl" "$BANC/outils-muet/systemctl"

sans_couture() {   # sans_couture <dossier de PATH>
	env -i PATH="$1" HOME="$BANC" \
		LEXOS_MODULES="$BANC/modules" LEXOS_X11_SOCKETS="$BANC/x11" \
		LEXOS_BUILD_CONF="$BANC/build.conf" LEXOS_SHELL_DIR="$SHELL_DIR" \
		sh -c '. "$0"; if session_graphique_absente; then echo oui; else echo non; fi' "$SG" 2>&1
}

VU_MUET="$(sans_couture "$BANC/outils-muet")"
[ "$VU_MUET" = "non" ] \
	&& ok "systemctl muet : on ne conclut PAS à la panne" \
	|| non "systemd muet, et on annonce quand même une panne : le doute penche du côté de l'alarme (« $VU_MUET »)"

VU_SANS="$(sans_couture "$BANC/outils")"
[ "$VU_SANS" = "non" ] \
	&& ok "…et sans systemctl du tout non plus (machine sans systemd, conteneur)" \
	|| non "sans systemctl, on annonce une panne sur une machine dont on ne sait rien (« $VU_SANS »)"

VU_ILLISIBLE="$(dire LEXOS_MODULES="$BANC/pas-de-modules")"
case "$VU_ILLISIBLE" in
	*"PAS PU lire la liste des modules"*)
		ok "/proc/modules illisible : le message le DIT au lieu d'écrire « Mesuré »" ;;
	*"Mesuré : AUCUN pilote"*)
		non "le message écrit « Mesuré : AUCUN pilote » sur une liste qu'il n'a pas pu lire" ;;
	*) non "le cas « modules illisibles » ne donne rien de reconnaissable : $(printf '%s' "$VU_ILLISIBLE" | tail -2 | tr '\n' ' ')" ;;
esac

# ===========================================================================
titre "8. UN PILOTE LIVRÉ SANS SON MODULE NOYAU, ÇA SE DIT"
# ===========================================================================
#  Le hook 0260 écrit QUATRE clés, et le message n'en lisait que deux. Sur une
#  ISO où le pilote est installé mais dont le module noyau n'a jamais été
#  compilé — c'est arrivé, deux ISO ont été livrées sur la foi d'un « apt a
#  dit oui » — le message annonçait « cette ISO embarque POURTANT le pilote
#  NVIDIA 610.43.02 ». Une consolation fausse, qui envoie chercher du côté du
#  BIOS alors qu'il n'y a rien à y trouver.
printf 'LEXOS_NVIDIA_ETAT="ok"\nLEXOS_NVIDIA_VERSION="580.82.07"\nLEXOS_NVIDIA_MODULE="non"\n' > "$BANC/build.conf"
VU_MOD="$(dire)"
case "$VU_MOD" in
	*"MODULE"*"pas été compilé"*"autre ISO"*)
		ok "pilote sans module noyau : le message dit qu'il faut une autre ISO" ;;
	*"embarque pourtant le pilote"*)
		non "le message console comme si le pilote allait servir, alors que rien ne peut prendre la carte" ;;
	*) non "le cas « module absent » ne donne rien de reconnaissable : $(printf '%s' "$VU_MOD" | tail -2 | tr '\n' ' ')" ;;
esac
rm -f "$BANC/build.conf"

printf '\n\033[1m%d réussis, %d échoués, %d non mesurés\033[0m\n' "$REUSSIS" "$ECHOUES" "$MUETS"
[ "$ECHOUES" -eq 0 ]
