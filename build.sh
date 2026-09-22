#!/usr/bin/env bash
# =============================================================================
#  LexOS — script de construction de l'ISO
# =============================================================================
#  Usage :
#     sudo ./build.sh                      # saveur par défaut (lexos.conf)
#     sudo ./build.sh --flavour full       # minimal | standard | dev | full
#     sudo ./build.sh --suite trixie       # change la base Debian
#     sudo ./build.sh --check              # vérifie l'environnement et sort
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# --- Couleurs ----------------------------------------------------------------
if [[ -t 1 ]]; then
	C_RESET=$'\033[0m'; C_ORANGE=$'\033[38;5;208m'; C_DIM=$'\033[2m'
	C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
else
	C_RESET=''; C_ORANGE=''; C_DIM=''; C_RED=''; C_GREEN=''; C_YELLOW=''
fi

info()  { printf '%s[LexOS]%s %s\n' "$C_ORANGE" "$C_RESET" "$*"; }
ok()    { printf '%s  ok  %s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()  { printf '%s warn %s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()   { printf '%s fail %s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

# --- Bannière ----------------------------------------------------------------
banner() {
	printf '%s' "$C_ORANGE"
	cat <<'EOF'
   __         _____ _____
  / /  _____ / __  |  ___|
 / /  / _ \ \/ / | | |___
/ /__|  __/>  <  | |___  |
\____/\___/_/\_\ |_____/    build system
EOF
	printf '%s\n' "$C_RESET"
}

# --- Arguments ---------------------------------------------------------------
CHECK_ONLY=0
CLI_FLAVOUR=""
CLI_SUITE=""
CLI_ARCH=""
#  Les deux soupapes des hooks qui font échouer la construction. Elles se
#  posent aussi dans lexos.conf, pour qu'une machine de construction puisse
#  les tenir sans les retaper ; le drapeau a le dernier mot.
SANS_PILOTE=0
SANS_SECOURS=0""
LB_EXTRA=()

while [[ $# -gt 0 ]]; do
	case "$1" in
		-f|--flavour) CLI_FLAVOUR="${2:-}"; shift 2 ;;
		-s|--suite)   CLI_SUITE="${2:-}";   shift 2 ;;
		-a|--arch)    CLI_ARCH="${2:-}";    shift 2 ;;
		-c|--check)   CHECK_ONLY=1;         shift ;;
		-h|--help)
			cat <<-'USAGE'
			LexOS — construction de l'ISO

			  sudo ./build.sh                     saveur par défaut (lexos.conf)
			  sudo ./build.sh --flavour full      minimal | standard | dev | full | gaming | pro
			  sudo ./build.sh --suite trixie      change la base Debian
			  sudo ./build.sh --arch amd64        architecture cible
			  sudo ./build.sh --check             vérifie l'environnement et sort
			  sudo ./build.sh --sans-pilote       accepte une ISO « pro » SANS pilote NVIDIA
			                                      (sinon la construction échoue — voir hook 0260)
			  sudo ./build.sh --sans-secours      accepte un menu UEFI SANS entrée de secours
			                                      (sinon la construction échoue — voir hook 0910)
			  ./build.sh --help                   cette aide

			Tout ce qui suit « -- » est transmis tel quel à `lb build`.
			USAGE
			exit 0 ;;
		#  ═══ LES DEUX SOUPAPES, EN DRAPEAUX ET PAS EN VARIABLES ═══
		#  Deux hooks font désormais ÉCHOUER la construction : 0260 (une ISO
		#  « pro » sans pilote NVIDIA) et 0910 (un menu UEFI sans entrée de
		#  secours). Les deux annonçaient une porte de sortie par variable
		#  d'environnement. MESURÉ : les deux portes étaient FERMÉES.
		#    · « sudo ./build.sh » — la seule façon documentée de construire —
		#      efface l'environnement (« Defaults env_reset » dans sudoers) ;
		#    · et les hooks .chroot sont lancés par live-build sous
		#      « env -i », qui repart d'un environnement vide : seul un
		#      config/environment.chroot passerait, et ce dépôt n'en a pas ;
		#    · et build.conf est RÉÉCRIT plus bas depuis un gabarit figé, donc
		#      y poser la clé à la main ne survivait pas à la construction.
		#  Un « exit 1 » dont le remède ne marche pas, c'est un verrou sans
		#  clé : le jour où il se déclenche, la seule issue serait d'éditer le
		#  hook et de repousser — c'est-à-dire de désactiver le contrôle,
		#  exactement ce qu'on voulait éviter.
		#  Un DRAPEAU, lui, traverse sudo : c'est un argument, pas un
		#  environnement.
		--sans-pilote)  SANS_PILOTE=1 ;;
		--sans-secours) SANS_SECOURS=1 ;;
		--) shift; LB_EXTRA+=("$@"); break ;;
		*)  die "Option inconnue : $1  (essaie --help)" ;;
	esac
done

banner

# --- Chargement de la config -------------------------------------------------
[[ -f lexos.conf ]] || die "lexos.conf introuvable — tu n'es pas à la racine du projet ?"
# shellcheck source=lexos.conf
source ./lexos.conf

[[ -n "$CLI_FLAVOUR" ]] && LEXOS_FLAVOUR="$CLI_FLAVOUR"
[[ -n "$CLI_SUITE"   ]] && LEXOS_DEBIAN_SUITE="$CLI_SUITE"
[[ -n "$CLI_ARCH"    ]] && LEXOS_ARCH="$CLI_ARCH"

#  ═══ LES DEUX SOUPAPES, RÉSOLUES ICI, UNE FOIS ═══
#  lexos.conf peut les poser ; le drapeau a le dernier mot. Ensuite :
#    · LEXOS_NVIDIA_FACULTATIF part dans build.conf (plus bas), parce que le
#      hook 0260 tourne DANS le chroot, où l'environnement de l'appelant
#      n'arrive pas — mais où build.conf, lui, est copié et sourcé ;
#    · LEXOS_SECOURS_FACULTATIF part dans l'ENVIRONNEMENT, parce que le hook
#      0910 est un .hook.binary : il tourne sur l'hôte, comme un enfant de
#      « lb build », donc il hérite de ce qu'on exporte ici.
#  Deux hooks, deux mécaniques, et c'est justement ce qui rendait le défaut
#  invisible à la relecture : ils avaient l'air d'avoir la même porte.
[[ "$SANS_PILOTE"  = "1" ]] && LEXOS_NVIDIA_FACULTATIF=1
[[ "$SANS_SECOURS" = "1" ]] && LEXOS_SECOURS_FACULTATIF=1
LEXOS_NVIDIA_FACULTATIF="${LEXOS_NVIDIA_FACULTATIF:-0}"
LEXOS_SECOURS_FACULTATIF="${LEXOS_SECOURS_FACULTATIF:-0}"
export LEXOS_FLAVOUR LEXOS_DEBIAN_SUITE LEXOS_ARCH LEXOS_SECOURS_FACULTATIF

if [[ "$LEXOS_NVIDIA_FACULTATIF" = "1" ]]; then
	warn "--sans-pilote : une ISO « pro » sans pilote NVIDIA sera ACCEPTÉE."
	warn "               Elle partira marquée « absent-accepte », et le dira."
fi
if [[ "$LEXOS_SECOURS_FACULTATIF" = "1" ]]; then
	warn "--sans-secours : un menu UEFI sans entrée de secours sera ACCEPTÉ."
	warn "                 Une machine dont l'affichage ne démarre pas n'aura"
	warn "                 alors aucune façon d'arriver jusqu'à une console."
fi

case "$LEXOS_FLAVOUR" in
	minimal|standard|dev|full|gaming|pro) ;;
	*) die "Saveur inconnue : '$LEXOS_FLAVOUR' (minimal | standard | dev | full | gaming | pro)" ;;
esac

info "Distribution : ${LEXOS_NAME} ${LEXOS_VERSION} « ${LEXOS_CODENAME} »"
info "Socle        : Debian ${LEXOS_DEBIAN_SUITE} / ${LEXOS_ARCH} (noyau ${LEXOS_KERNEL_CHANNEL})"
info "Saveur       : ${LEXOS_FLAVOUR}"

# --- Vérification de l'environnement ----------------------------------------
check_env() {
	local missing=() c
	info "Vérification de l'environnement de build…"

	[[ "$(uname -s)" == "Linux" ]] || die "La construction d'une ISO Debian exige un hôte Linux."

	for c in lb debootstrap xorriso mksquashfs rsync wget gpg; do
		if command -v "$c" >/dev/null 2>&1; then
			ok "$c"
		else
			missing+=("$c")
		fi
	done

	if ((${#missing[@]})); then
		printf '%s\n' "" >&2
		warn "Outils manquants : ${missing[*]}"
		cat >&2 <<-EOF

		    Sur Debian / Ubuntu, installe-les avec :

		      sudo apt update
		      sudo apt install -y live-build debootstrap xorriso squashfs-tools \\
		                          rsync wget gnupg ca-certificates \\
		                          syslinux-common isolinux grub-efi-amd64-bin \\
		                          grub-pc-bin mtools dosfstools librsvg2-bin

		EOF
		return 1
	fi

	# live-build >= 1:20230502 pour --uefi-secure-boot
	local lbver
	lbver="$(dpkg-query -W -f='${Version}' live-build 2>/dev/null || echo '?')"
	ok "live-build ${lbver}"

	# Espace disque : ~12 Go conseillés
	local avail_kb avail_gb
	avail_kb="$(df -Pk . | awk 'NR==2{print $4}')"
	avail_gb=$(( avail_kb / 1024 / 1024 ))
	if (( avail_gb < 12 )); then
		warn "Seulement ${avail_gb} Go libres ici — 12 Go minimum recommandés."
	else
		ok "espace disque : ${avail_gb} Go libres"
	fi

	if [[ "${EUID}" -ne 0 ]]; then
		warn "live-build doit tourner en root : relance avec sudo."
		return 1
	fi
	ok "privilèges root"
	return 0
}

if ! check_env; then
	(( CHECK_ONLY )) && exit 1
	die "Environnement incomplet — corrige les points ci-dessus puis relance."
fi

if (( CHECK_ONLY )); then
	info "Environnement prêt. ✔"
	exit 0
fi

# --- Génération des fichiers dérivés ----------------------------------------
info "Génération des fichiers de branding…"

BUILD_DATE="$(date -u '+%Y-%m-%d')"
BUILD_ID="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo 'nogit')"

mkdir -p config/includes.chroot/etc/lexos
cat > config/includes.chroot/etc/lexos/build.conf <<EOF
# Généré par build.sh — ne pas éditer à la main.
LEXOS_NAME="${LEXOS_NAME}"
LEXOS_ID="${LEXOS_ID}"
LEXOS_VERSION="${LEXOS_VERSION}"
LEXOS_CODENAME="${LEXOS_CODENAME}"
LEXOS_TAGLINE="${LEXOS_TAGLINE}"
LEXOS_HOME_URL="${LEXOS_HOME_URL}"
LEXOS_BUG_URL="${LEXOS_BUG_URL}"
LEXOS_DEBIAN_SUITE="${LEXOS_DEBIAN_SUITE}"
LEXOS_FLAVOUR="${LEXOS_FLAVOUR}"
LEXOS_ARCH="${LEXOS_ARCH}"
LEXOS_TIMEZONE="${LEXOS_TIMEZONE}"
LEXOS_LOCALE="${LEXOS_LOCALE}"
LEXOS_KEYBOARD_LAYOUT="${LEXOS_KEYBOARD_LAYOUT}"
LEXOS_KEYBOARD_VARIANT="${LEXOS_KEYBOARD_VARIANT}"
LEXOS_BRAND="${LEXOS_BRAND}"
LEXOS_LICENSE="${LEXOS_LICENSE}"
LEXOS_ACCENT_NAME="${LEXOS_ACCENT_NAME}"
LEXOS_BG="${LEXOS_BG}"
LEXOS_FG="${LEXOS_FG}"
LEXOS_TERM_FG="${LEXOS_TERM_FG}"
LEXOS_GTK_BASE_THEME="${LEXOS_GTK_BASE_THEME}"
LEXOS_ICON_THEME="${LEXOS_ICON_THEME}"
LEXOS_CRT_EFFECTS="${LEXOS_CRT_EFFECTS}"
LEXOS_DOCK_POSITION="${LEXOS_DOCK_POSITION}"
LEXOS_PERF_PROFILE="${LEXOS_PERF_PROFILE}"
LEXOS_WIFI_AUTO_OPEN="${LEXOS_WIFI_AUTO_OPEN}"
LEXOS_DISK_ENCRYPTION="${LEXOS_DISK_ENCRYPTION}"
LEXOS_KERNEL_CHANNEL="${LEXOS_KERNEL_CHANNEL}"
LEXOS_NVIDIA_BRANCH="${LEXOS_NVIDIA_BRANCH:-}"
LEXOS_NVIDIA_FACULTATIF="${LEXOS_NVIDIA_FACULTATIF}"
LEXOS_BUILD_DATE="${BUILD_DATE}"
LEXOS_BUILD_ID="${BUILD_ID}"
EOF
ok "etc/lexos/build.conf"

# branding/ est la source de vérité : on le recopie dans l'arbre de l'image.
BRAND_DST="config/includes.chroot/usr/share/lexos/branding"
mkdir -p "$BRAND_DST"
rm -f "$BRAND_DST"/*
cp branding/*.svg branding/*.png "$BRAND_DST"/ 2>/dev/null || true
#  ═══ LES .jpg — ET C'EST LE PLUS GROS TROU QU'ON AIT TROUVÉ ICI ═══
#  Cette ligne n'existait pas. Les deux fonds d'écran d'Alex,
#  fond-mascotte.jpg et fond-tilexal-banniere.jpg, sont des .jpg : ils
#  n'arrivaient donc JAMAIS dans le chroot. Le hook 0300 les cherche à
#  « /usr/share/lexos/branding/ », ne les trouvait pas, imprimait
#  « pas de fond mascotte : branding/fond-mascotte.jpg absent » — et
#  passait. Aucune ISO publiée n'a jamais contenu ces deux fonds d'écran.
#
#  POURQUOI PERSONNE NE L'A VU. Le banc tests/test_lexos_fonds_alex.sh est
#  vert depuis le début : il recopie lui-même les deux fichiers depuis
#  branding/ dans sa fausse arborescence, puis vérifie que le hook les
#  découpe bien. Il éprouve la RECETTE et jamais la LIVRAISON. Un banc peut
#  être juste et complet sur ce qu'il regarde, et laisser passer ce qu'il
#  ne regarde pas. Le contrôle qui manquait est maintenant dans
#  tests/test_lexos_images.sh : tout fichier qu'un hook lit sous $BRAND
#  doit être copié ici.
#
#  Mesuré avant correction, en rejouant ces lignes dans un dossier vide :
#  71 fichiers copiés, 0 .jpg.
cp branding/*.jpg branding/*.jpeg "$BRAND_DST"/ 2>/dev/null || true
#  Les .webp (mascottes rock et salut) et le .gif animé : le hook 0300 les
#  attend pour les convertir en PNG — sans cette ligne, sa boucle « *.webp »
#  tournait sur un dossier qui n'en avait aucun, en silence.
cp branding/*.webp branding/*.gif "$BRAND_DST"/ 2>/dev/null || true
#  Les images de l'animation Plymouth (démarrage) : un dossier, que le
#  « cp » sans -r du dessus ignorait — le thème animé retombait sur l'image
#  fixe sans le dire.
[ -d branding/mascot-anim-frames ] && cp -r branding/mascot-anim-frames "$BRAND_DST"/ 2>/dev/null
#  ═══ LA VIDÉO D'OUVERTURE EST UNE SOURCE DE CONSTRUCTION ═══
#  Le hook 0300 tourne DANS le chroot : il ne peut découper que ce qui s'y
#  trouve. Sans cette ligne, ouvrir-ordinateur.mp4 serait resté dans le
#  dépôt, le hook ne l'aurait jamais vue, et l'entrée en matière serait
#  tombée dans son repli à CHAQUE construction — en le disant, mais sans
#  que personne comprenne pourquoi. Le hook la RETIRE après le découpage :
#  7 Mo de vidéo n'ont rien à faire dans l'ISO, seules les images comptent.
cp branding/*.mp4 "$BRAND_DST"/ 2>/dev/null || true
ok "branding/ -> usr/share/lexos/branding ($(ls -1 "$BRAND_DST" | wc -l) fichiers)"

# --- Sélection de la saveur --------------------------------------------------
info "Assemblage des listes de paquets (saveur : ${LEXOS_FLAVOUR})…"
rm -f config/package-lists/zz-flavour-*.list.chroot

apply_flavour() {
	local f="$1" src count=0
	[[ -d "flavours/$f" ]] || return 0
	for src in "flavours/$f"/*.list.chroot; do
		[[ -e "$src" ]] || continue
		cp "$src" "config/package-lists/zz-flavour-$f-$(basename "$src")"
		count=$((count + 1))
	done
	ok "saveur '$f' : $count liste(s)"
}

# Toutes les saveurs de bureau reçoivent EXACTEMENT les mêmes listes.
#
# L'empilement d'avant creusait des trous que personne ne voyait : « pro »
# sautait la liste « full » (LibreOffice, VLC, GIMP, ffmpeg) et « dev » —
# la saveur du portable, celle sur laquelle on teste tout — sautait « full »,
# « gaming » ET « pro ». Le bureau essayé sur le portable n'était donc pas
# celui livré sur l'Alienware.
#
# Seule différence qui reste entre les ISO : le matériel. Le pilote NVIDIA
# propriétaire n'est embarqué que par la saveur « pro » (hook 0260) — le
# portable n'a pas de carte NVIDIA et le lui poser risquerait l'écran noir.
case "$LEXOS_FLAVOUR" in
	minimal)
		;;
	*)
		apply_flavour standard
		apply_flavour dev
		apply_flavour full
		apply_flavour gaming
		apply_flavour pro
		;;
esac

TOTAL_PKGS="$(cat config/package-lists/*.list.chroot 2>/dev/null \
	| grep -Ev '^\s*(#|$)' | sort -u | wc -l)"
OPT_DIR="config/includes.chroot/usr/share/lexos/optional-packages"
OPT_PKGS="$(cat "$OPT_DIR"/*.list 2>/dev/null | grep -Evc '^\s*(#|$)' || echo 0)"
ok "${TOTAL_PKGS} paquets stricts + ${OPT_PKGS} optionnels (best effort)"

# --- Droits d'exécution ------------------------------------------------------
chmod +x auto/config auto/build auto/clean 2>/dev/null || true
chmod +x config/hooks/normal/*.hook.chroot 2>/dev/null || true
chmod +x config/includes.chroot/usr/bin/* 2>/dev/null || true

# --- Construction ------------------------------------------------------------
info "lb config…"
lb config

info "lb build — ça va prendre 20 à 60 minutes et télécharger plusieurs Go."
START="$(date +%s)"
lb build "${LB_EXTRA[@]+"${LB_EXTRA[@]}"}"
END="$(date +%s)"

# --- Résultat ----------------------------------------------------------------
ISO="$(ls -1 ./*.iso 2>/dev/null | head -n1 || true)"
if [[ -n "$ISO" ]]; then
	sha256sum "$ISO" > "${ISO}.sha256"
	printf '\n'
	info "Terminé en $(( (END - START) / 60 )) min $(( (END - START) % 60 )) s"
	ok "ISO      : ${ISO}"
	ok "Taille   : $(du -h "$ISO" | cut -f1)"
	ok "SHA-256  : ${ISO}.sha256"
	printf '\n%sTester dans QEMU :%s\n  make test\n\n' "$C_DIM" "$C_RESET"
	printf '%sGraver sur clé USB :%s\n  sudo dd if=%s of=/dev/sdX bs=4M status=progress oflag=sync\n\n' \
		"$C_DIM" "$C_RESET" "$ISO"
else
	die "Aucune ISO produite — consulte build.log"
fi
