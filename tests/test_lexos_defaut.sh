#!/usr/bin/env bash
# =============================================================================
#  Éprouver les APPLICATIONS PAR DÉFAUT — la page qui ne faisait que lire
# =============================================================================
#  ALEX : « le contenu comme Ubuntu », puis « commence par applications par
#  défaut ».
#
#  CE QUE LA PAGE FAISAIT AVANT. Elle affichait cinq lignes — navigateur,
#  texte, image, PDF, musique, vidéo — lues à la main dans mimeapps.list, et
#  RIEN À CLIQUER. Pour changer quoi que ce soit, elle passait la main à
#  l'outil de XFCE. Sur la page d'Ubuntu, on choisit ; ici on regardait.
#
#  CE BANC ÉPROUVE LES TROIS ÉTAGES, ET IL LES FAIT TOURNER :
#    l'outil   — « lexos-defaut --json » publie-t-il les dix catégories ?
#    le moteur — « act_defaut » change-t-il VRAIMENT l'application en place ?
#    la page   — y a-t-il une liste déroulante par catégorie, branchée ?
#
#  POURQUOI UN DÉCOR PLUTÔT QUE LA MACHINE. Les applications proposées
#  dépendent de ce qui est installé : un banc qui exigerait « VLC » serait
#  vert chez l'un et rouge chez l'autre sans qu'aucun code n'ait changé. On
#  pose donc nos propres .desktop dans un HOME jetable et un faux xdg-mime
#  qui se souvient — alors AVANT et APRÈS sont mesurables partout, y compris
#  dans un conteneur d'intégration sans le moindre lecteur vidéo.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTIL="$RACINE/config/includes.chroot/usr/bin/lexos-defaut"
MOTEUR="$RACINE/config/includes.chroot/usr/lib/lexos/settings.py"
PAGE="$RACINE/config/includes.chroot/usr/share/lexos/settings/web/app.js"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
saute(){ printf '  \033[33m•\033[0m %s\n' "$1"; }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

for F in "$OUTIL" "$MOTEUR" "$PAGE"; do
	[ -r "$F" ] || { echo "introuvable : $F"; exit 1; }
done

# =============================================================================
#  LE DÉCOR — un HOME jetable, quatre applications à nous, deux faux outils
# =============================================================================
#  LE NOM PIÉGÉ N'EST PAS UNE COQUETTERIE. cmd_json écrit son JSON à la main
#  — lexos-defaut est du bash, il n'a pas de bibliothèque JSON — et les noms
#  d'applications sont la SEULE donnée qui ne vienne pas de nos propres
#  tables : ils sortent de fichiers .desktop du système, guillemets et
#  antislash compris. Un seul guillemet non échappé et la page entière reste
#  blanche, sans message. On en met donc un dans le décor.
FOYER="$BANC/foyer"
APPS="$FOYER/.local/share/applications"
mkdir -p "$APPS" "$BANC/bin"

ecrire_appli() { # fichier, nom français, types MIME
	cat > "$APPS/$1" <<-EOF
		[Desktop Entry]
		Type=Application
		Name=Bench
		Name[fr]=$2
		Exec=/bin/true
		MimeType=$3
	EOF
}
ecrire_appli banc-visionneuse.desktop 'Visionneuse du banc'    'image/jpeg;image/png;'
ecrire_appli banc-autre.desktop       'Autre visionneuse'      'image/jpeg;image/png;'
ecrire_appli banc-piege.desktop       'L'\''« outil » dit "bonjour" \ ok' 'image/jpeg;'
ecrire_appli banc-fureteur.desktop    'Fureteur du banc' \
	'text/html;x-scheme-handler/http;x-scheme-handler/https;'

#  DEUX CHEMINS D'ÉCRITURE, ET ILS NE SE RESSEMBLENT PAS. Pour le navigateur,
#  lexos-defaut appelle xdg-settings (qui règle text/html ET les schémas
#  http/https d'un seul geste) ; pour tout le reste, xdg-mime. Un banc qui
#  n'éprouverait que le second laisserait la moitié du travail sans filet.
cat > "$BANC/bin/xdg-mime" <<'FAUX'
#!/bin/sh
REG="${BANC_REG:?}"
case "$1" in
  default) shift; cible="$1"; shift
    for m in "$@"; do
      grep -v "^$m " "$REG" > "$REG.tmp" 2>/dev/null || :
      mv "$REG.tmp" "$REG" 2>/dev/null || :
      printf '%s %s\n' "$m" "$cible" >> "$REG"
    done ;;
  query) shift; [ "${1:-}" = default ] || exit 1; shift
    awk -v m="$1" '$1==m {print $2; f=1} END{exit !f}' "$REG" 2>/dev/null ;;
  *) exit 1 ;;
esac
FAUX
cat > "$BANC/bin/xdg-settings" <<'FAUX'
#!/bin/sh
REG="${BANC_NAV:?}"
case "$1 $2" in
  "set default-web-browser") printf '%s\n' "$3" > "$REG" ;;
  "get default-web-browser") cat "$REG" 2>/dev/null || : ;;
  *) exit 1 ;;
esac
FAUX
chmod +x "$BANC/bin/xdg-mime" "$BANC/bin/xdg-settings"
: > "$BANC/mimes"; : > "$BANC/nav"

export BANC_REG="$BANC/mimes" BANC_NAV="$BANC/nav"
CHEMIN="$BANC/bin:$RACINE/config/includes.chroot/usr/bin:$PATH"
lexdef() { PATH="$CHEMIN" HOME="$FOYER" bash "$OUTIL" "$@"; }

# =============================================================================
titre "1. « --json » — les dix catégories passent au reste du système"
# =============================================================================
if ! command -v python3 >/dev/null 2>&1; then
	saute "python3 absent : le JSON n'a PAS été éprouvé"
	ETAT=""
else
	ETAT="$(lexdef --json 2>/dev/null)"
	printf '%s' "$ETAT" > "$BANC/etat.json"
	if printf '%s' "$ETAT" | python3 -m json.tool >/dev/null 2>&1; then
		ok "« lexos-defaut --json » rend du JSON valide"
	else
		non "« --json » ne rend pas du JSON valide :\\n$ETAT"
		ETAT=""
	fi
fi

if [ -n "$ETAT" ]; then
	LU="$(python3 - "$BANC/etat.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
cats = d.get("categories", [])
cles = [c.get("cle") for c in cats]
#  Les dix catégories, nommées : un simple « au moins six » laisserait passer
#  la disparition silencieuse du terminal ou des archives.
attendues = ["navigateur", "courriel", "video", "audio", "images",
             "texte", "fichiers", "terminal", "archives", "pdf"]
print("CLES", "oui" if cles == attendues else "NON:%s" % cles)
#  Chaque catégorie porte les quatre champs dont la page se sert. Une
#  catégorie sans « choix » ferait planter la page sur un « .length ».
champs = all(all(k in c for k in ("cle", "titre", "courant", "courant_nom", "choix"))
             for c in cats)
print("CHAMPS", "oui" if champs else "non")
img = next((c for c in cats if c["cle"] == "images"), {"choix": []})
noms = [x["nom"] for x in img["choix"]]
ids = [x["id"] for x in img["choix"]]
print("NOTRES", "oui" if {"banc-visionneuse.desktop", "banc-autre.desktop",
                          "banc-piege.desktop"} <= set(ids) else "NON:%s" % ids)
#  LE NOM PIÉGÉ, CARACTÈRE POUR CARACTÈRE. Qu'il soit « présent » ne suffit
#  pas : un échappement de travers rendrait « ok » sans l'antislash, et la
#  page afficherait un nom faux sans que rien ne soit rouge.
piege = 'L\'« outil » dit "bonjour" \\ ok'
print("PIEGE", "oui" if piege in noms else "NON:%s" % noms)
print("TOTAL", d.get("total"))
PY
)"
	case "$LU" in
		*"CLES oui"*)   ok "les dix catégories sont publiées, dans l'ordre de l'outil" ;;
		*) non "les catégories publiées ne sont pas les dix attendues (${LU#*CLES })" ;;
	esac
	case "$LU" in
		*"CHAMPS oui"*) ok "chacune porte cle, titre, courant, courant_nom et choix" ;;
		*) non "des champs manquent : la page casserait sur une catégorie incomplète" ;;
	esac
	case "$LU" in
		*"NOTRES oui"*) ok "les applications posées dans le décor sont proposées pour « images »" ;;
		*) non "les applications du décor ne sont pas vues (${LU#*NOTRES })" ;;
	esac
	case "$LU" in
		*"PIEGE oui"*)  ok "un nom avec guillemets, chevrons et antislash traverse le JSON intact" ;;
		*) non "le nom piégé n'a pas survécu à l'échappement (${LU#*PIEGE })" ;;
	esac
	case "$LU" in
		*"TOTAL 10"*)   ok "le total annoncé (10) est celui des catégories rendues" ;;
		*) non "le total annoncé ne vaut pas 10" ;;
	esac
fi

# =============================================================================
titre "2. LES GESTES CHANGENT VRAIMENT L'APPLICATION — on les fait tourner"
# =============================================================================
#  On n'ouvre pas le code pour y chercher une fonction : une fonction qui ne
#  fait rien passerait ce contrôle-là. On appelle l'action du moteur, comme
#  la page le fait, et on regarde l'application en place AVANT et APRÈS.
if ! command -v python3 >/dev/null 2>&1; then
	saute "python3 absent : les gestes n'ont PAS été éprouvés"
else
	cat > "$BANC/gestes.py" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import settings

try:
    def courant(cle):
        for c in settings._defaut_etat().get("categories", []):
            if c.get("cle") == cle:
                return c.get("courant") or ""
        return None

    #  ═══ LE CHEMIN xdg-mime ═══
    avant = courant("images")
    r = settings.act_defaut("images:banc-visionneuse.desktop")
    apres = courant("images")
    print(("OK|" if (r.get("ok") and apres == "banc-visionneuse.desktop"
                     and apres != avant) else "NON|") +
          "« images » passe de « %s » à « %s »" % (avant or "rien", apres or "rien"))

    #  ET ON EN CHANGE UNE DEUXIÈME FOIS : un réglage qui ne saurait qu'écrire la
    #  première valeur passerait le contrôle ci-dessus.
    r = settings.act_defaut("images:banc-autre.desktop")
    print(("OK|" if (r.get("ok") and courant("images") == "banc-autre.desktop") else "NON|") +
          "on peut en changer une deuxième fois (%s)" % courant("images"))

    #  ═══ LE CHEMIN xdg-settings ═══ — le navigateur ne passe pas par xdg-mime.
    avant = courant("navigateur")
    r = settings.act_defaut("navigateur:banc-fureteur.desktop")
    print(("OK|" if (r.get("ok") and courant("navigateur") == "banc-fureteur.desktop"
                     and courant("navigateur") != avant) else "NON|") +
          "« navigateur » passe de « %s » à « %s »" % (avant or "rien", courant("navigateur")))

    #  ═══ CE QUI DOIT ÊTRE REFUSÉ ═══
    #  Ces valeurs viennent d'une page web. Aucune n'atteint un shell — _run()
    #  reçoit une liste d'arguments, il n'y en a pas — mais toutes doivent être
    #  refusées AVEC UN MOTIF que la page puisse montrer.
    #
    #  ET LE REFUS DOIT VENIR DES PARAMÈTRES. lexos-defaut refuse lui aussi une
    #  application absente (« Aucune application… »), donc un contrôle qui se
    #  contenterait de « ok vaut faux » serait VERT même si le moteur ne
    #  vérifiait plus rien — la faute exacte qu'a connue le banc du clavier. On
    #  exige donc le motif du moteur, celui qui nomme la catégorie.
    for mauvais, quoi in (
            ("images:pas-installee.desktop", "une application qui n'existe pas"),
            ("texte:banc-visionneuse.desktop", "une application proposée pour une AUTRE catégorie"),
            ("inconnue:banc-visionneuse.desktop", "une catégorie inventée"),
            ("images:; rm -rf /", "une commande glissée à la place du nom")):
        r = settings.act_defaut(mauvais)
        motif = r.get("erreur", "")
        print(("OK|" if (not r.get("ok") and "n'est pas proposée pour" in motif) else "NON|") +
              "refusé PAR LES PARAMÈTRES : %s (%s)" % (quoi, motif or "ACCEPTÉ !"))

    for mauvais, quoi in (("images:", "une application vide"),
                          (":banc-autre.desktop", "une catégorie vide"),
                          ("", "rien du tout")):
        r = settings.act_defaut(mauvais)
        print(("OK|" if (not r.get("ok") and "il faut une catégorie" in r.get("erreur", ""))
               else "NON|") + "refusé : %s (%s)" % (quoi, r.get("erreur", "ACCEPTÉ !")))

    #  ═══ LES ANCIENS NOMS SONT TOUJOURS SERVIS ═══
    #  D'autres endroits de la page lisent « navigateur » et « assoc ». Les
    #  renommer en silence aurait vidé ces lignes sans qu'une seule erreur ne le
    #  dise — un écran qui ment est pire qu'un écran qui plante.
    e = settings._defaut_etat()
    print(("OK|" if e.get("navigateur") == "banc-fureteur" else "NON|") +
          "l'ancien nom « navigateur » est encore servi (%s)" % e.get("navigateur"))
    print(("OK|" if e.get("assoc", {}).get("image") == "banc-autre" else "NON|") +
          "l'ancienne table « assoc » est encore servie (%s)" % e.get("assoc"))
except Exception as _e:
    #  UN PLANTAGE EST UN ROUGE, PAS UN SILENCE. Sans ce filet, une exception
    #  au milieu du script emporte tous les contrôles qui suivent : le banc
    #  affiche moins de coches et reste vert.
    print("NON|le banc s'est arrêté : %s: %s" % (type(_e).__name__, _e))
print("FIN|")

PY
	SORTIE_G="$(cd "$RACINE" && PATH="$CHEMIN" HOME="$FOYER" \
		python3 "$BANC/gestes.py" \
		"$RACINE/config/includes.chroot/usr/lib/lexos" 2>/dev/null \
		| grep -E '^(OK|NON|FIN)\|' || true)"
	#  LA SENTINELLE. Sans elle, un banc qui S'ARRÊTE au milieu reste VERT :
	#  les contrôles déjà écrits passent, ceux qui n'ont jamais été atteints
	#  disparaissent en silence — il y a juste moins de coches. C'est ce qui
	#  est arrivé ici : retirer la vérification du nom de compte faisait lever
	#  une KeyError au contrôle suivant, et le banc n'a rien vu du tout.
	#  Le script rend une dernière ligne « FIN| » ; son absence est un rouge.
	if [ -z "$SORTIE_G" ]; then
		non "les gestes n'ont rien rendu — le moteur n'a pas pu être appelé"
	elif ! printf '%s\n' "$SORTIE_G" | grep -q '^FIN|'; then
		non "le banc s'est arrêté avant la fin — des contrôles n'ont jamais tourné"
		while IFS='|' read -r V M; do
			[ "$V" = "NON" ] && non "$M"
		done <<EOF
$SORTIE_G
EOF
	else
		while IFS='|' read -r V M; do
			case "$V" in
				OK)  ok "$M" ;;
				NON) non "$M" ;;
			esac
		done <<EOF
$SORTIE_G
EOF
	fi
fi

#  ═══ ON REDEMANDE L'ÉTAT, MAINTENANT QU'IL Y A DES RÉGLAGES EN PLACE ═══
#  La page se rend plus bas sur CE fichier-ci, pas sur celui d'avant. Sur un
#  état tout neuf, aucune catégorie n'a d'application en place : le contrôle
#  « c'est bien la bonne qui est cochée » serait alors vrai sans rien vérifier,
#  et celui du « Choisir… » compterait toutes les listes. Après les gestes,
#  deux catégories sont réglées et deux ne le sont pas — les deux contrôles
#  peuvent enfin échouer.
if [ -n "${ETAT:-}" ]; then
	lexdef --json > "$BANC/etat.json" 2>/dev/null
fi

# =============================================================================
titre "3. LA PAGE A DE QUOI CHOISIR — on la rend pour de vrai"
# =============================================================================
#  Ici on ne greppe pas le code : les listes déroulantes de cette page
#  DÉPENDENT DES DONNÉES — une catégorie sans application candidate n'en
#  produit aucune. Un grep de « <select » serait donc vert sur une page qui
#  n'en affiche jamais. On charge app.js pour de vrai, on lui donne l'état
#  que l'outil vient de rendre, et on lit le HTML — c'est ce qu'Alex voit.
if ! command -v node >/dev/null 2>&1 || [ ! -s "$BANC/etat.json" ]; then
	saute "node absent (ou pas d'état) : la page n'a PAS été rendue"
else
	cat > "$BANC/rendu.js" <<'JS'
"use strict";
const fs = require("fs"), vm = require("vm");
const source = fs.readFileSync(process.argv[2], "utf8")
  //  « etat » est un « let » de portée fichier : invisible du dehors, mais
  //  visible d'une ligne ajoutée DANS le même fichier. Même procédé que les
  //  autres bancs de page de ce dépôt.
  + "\n;globalThis.__banc = { contenu, pose: e => { etat = e; }, nav: NAV };\n";
const el = () => ({ innerHTML:"", textContent:"", hidden:true, style:{}, dataset:{},
                    classList:{add(){},remove(){},toggle(){}},
                    querySelectorAll:()=>[], appendChild(){}, focus(){} });
const bac = vm.createContext({
  document:{ getElementById:()=>el(), querySelectorAll:()=>[], body:el(),
             documentElement:{style:{setProperty(){}},dataset:{}}, addEventListener(){} },
  location:{hash:""}, window:{confirm:()=>true},
  fetch:()=>Promise.reject(new Error("pas de pont dans le banc")),
  requestAnimationFrame:()=>0, setTimeout, clearTimeout, console });
bac.globalThis = bac;
vm.runInContext(source, bac, {filename:"app.js"});
const T = bac.__banc;

const dit = (bon, m) => console.log((bon ? "OK|" : "NON|") + m);

try {
  const etat = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));
  T.pose({ defaut: etat });
  const h = T.contenu("defaut");

  const avecChoix = etat.categories.filter(c => c.choix && c.choix.length);
  //  LE DÉCOR DOIT POUVOIR FAIRE ÉCHOUER LES CONTRÔLES QUI SUIVENT. S'il ne
  //  contenait que des catégories non réglées, « c'est la bonne qui est cochée »
  //  serait vrai sans rien vérifier. On l'exige, plutôt que de le supposer.
  dit(avecChoix.some(c => c.courant) && avecChoix.some(c => !c.courant),
      "le décor mêle des catégories réglées et non réglées — les contrôles peuvent échouer");
  const sans      = etat.categories.filter(c => !c.choix || !c.choix.length);
  const listes = (h.match(/<select /g) || []).length;
  dit(listes === avecChoix.length,
      `une liste déroulante par catégorie qui a des candidates (${listes}/${avecChoix.length})`);

  //  CHAQUE liste appelle l'action, avec SA propre clé. Une page qui n'en
  //  brancherait qu'une seule aurait le même nombre de « <select » que celle-ci.
  const branchees = avecChoix.filter(c =>
    h.includes(`setDefautAppli('${c.cle}', this.value)`)).length;
  dit(branchees === avecChoix.length,
      `chacune appelle setDefautAppli avec sa catégorie (${branchees}/${avecChoix.length})`);

  //  L'IDENTIFIANT DE L'APPLICATION NE RENTRE PAS DANS LE CODE JS de l'attribut :
  //  il passe par « this.value ». C'est ce qui fait qu'un .desktop au nom tordu
  //  ne peut pas casser l'attribut onchange — value="" l'échappe, une chaîne JS
  //  collée à la main ne l'aurait pas fait.
  dit(!/setDefautAppli\('[^']*', *['"]/.test(h),
      "l'identifiant passe par this.value, jamais collé dans le code de l'attribut");

  //  L'APPLICATION EN PLACE EST CELLE QUI EST COCHÉE. Sans cela, la page
  //  afficherait la première de la liste comme si elle était le choix courant.
  const marquees = avecChoix.filter(c => !c.courant ||
    h.includes(`value="${c.courant}" selected>`)).length;
  dit(marquees === avecChoix.length,
      `l'application en place est celle qui est sélectionnée (${marquees}/${avecChoix.length})`);

  //  ET « Choisir… » EXACTEMENT LÀ OÙ RIEN N'EST RÉGLÉ, ni ailleurs.
  const attendu = avecChoix.filter(c => !c.courant).length;
  const trouve  = (h.match(/Choisir…/g) || []).length;
  dit(trouve === attendu,
      `« Choisir… » n'apparaît que là où rien n'est réglé (${trouve}/${attendu})`);

  //  UNE CATÉGORIE SANS CANDIDATE LE DIT. Une ligne vide laisserait croire à
  //  une panne ; le terminal, lui, a sa propre explication — il n'a aucun type
  //  MIME, XFCE le range dans son réglage à part.
  const muettes = sans.filter(c => c.cle !== "terminal").length;
  const dites = (h.match(/Aucune application installée/g) || []).length;
  dit(dites === muettes,
      `les catégories sans candidate le disent (${dites}/${muettes})`);
  dit(!sans.some(c => c.cle === "terminal") ||
      h.includes("Le terminal n'a pas de type de fichier"),
      "le terminal explique pourquoi il n'a pas de liste");

  //  LE NOM PIÉGÉ EST ÉCHAPPÉ EN HTML. Il a déjà traversé le JSON ; il lui
  //  reste à traverser le rendu sans ouvrir un attribut.
  dit(!/dit "bonjour"/.test(h) && h.includes("&quot;bonjour&quot;"),
      "un nom à guillemets est échappé dans le HTML");

  //  L'OUTIL MUET NE DONNE PAS UNE PAGE VIDE.
  T.pose({ defaut: {} });
  dit(T.contenu("defaut").includes("lexos-defaut n'a pas répondu"),
      "si l'outil ne répond pas, la page le dit au lieu de rester blanche");

  //  ET LA SECTION EST ATTEIGNABLE : une page parfaite dans un menu qui ne la
  //  nomme pas n'existe pas.
  dit(T.nav.some(g => g.items.some(i => i[0] === "defaut")),
      "« Applications par défaut » est dans le menu de gauche");
} catch (e) {
  /*  UN PLANTAGE EST UN ROUGE, PAS UN SILENCE. Sans ce filet, une exception au
      milieu du rendu emporte tous les contrôles qui suivent : le banc affiche
      moins de coches et reste vert. */
  console.log("NON|le rendu s'est arrêté : " + (e && e.message || e));
}
console.log("FIN|");
JS
	SORTIE_P="$(node "$BANC/rendu.js" "$PAGE" "$BANC/etat.json" 2>&1 \
		| grep -E '^(OK|NON|FIN)\|' || true)"
	#  LA SENTINELLE. Sans elle, un banc qui S'ARRÊTE au milieu reste VERT :
	#  les contrôles déjà écrits passent, ceux qui n'ont jamais été atteints
	#  disparaissent en silence — il y a juste moins de coches. C'est ce qui
	#  est arrivé ici : retirer la vérification du nom de compte faisait lever
	#  une KeyError au contrôle suivant, et le banc n'a rien vu du tout.
	#  Le script rend une dernière ligne « FIN| » ; son absence est un rouge.
	if [ -z "$SORTIE_P" ]; then
		non "la page n'a rien rendu — app.js n'a pas pu être chargé"
	elif ! printf '%s\n' "$SORTIE_P" | grep -q '^FIN|'; then
		non "le banc s'est arrêté avant la fin — des contrôles n'ont jamais tourné"
		while IFS='|' read -r V M; do
			[ "$V" = "NON" ] && non "$M"
		done <<EOF
$SORTIE_P
EOF
	else
		while IFS='|' read -r V M; do
			case "$V" in
				OK)  ok "$M" ;;
				NON) non "$M" ;;
			esac
		done <<EOF
$SORTIE_P
EOF
	fi
fi

# =============================================================================
titre "4. UNE SEULE SOURCE — on ne recopie pas les types de fichiers"
# =============================================================================
#  La version précédente de _defaut_etat() relisait mimeapps.list avec sa
#  PROPRE table de cinq types MIME, pendant que lexos-defaut en portait dix
#  catégories. Deux copies de la même connaissance finissent toujours par ne
#  plus dire la même chose — c'est le raisonnement déjà tenu ici pour
#  lexos-clavier et lexos-distant, et la faute qui a donné trois palettes de
#  panneaux dans ce dépôt.
#  ON GREPPE UN FICHIER, PAS UN TUYAU : « printf … | grep -q » fait fermer le
#  tuyau par grep, printf prend un SIGPIPE, et sous « pipefail » la commande
#  rend 141 — un rouge qui ne parle pas du code, et qui va et vient d'une
#  exécution à l'autre. Ce dépôt a déjà payé ce piège au banc du clavier.
sed 's|#.*$||' "$MOTEUR" > "$BANC/moteur.py"
sed 's|//.*$||' "$PAGE"  > "$BANC/page.js"

grep -q 'lexos-defaut' "$BANC/moteur.py" \
	&& ok "le moteur demande son état à lexos-defaut" \
	|| non "le moteur ne passe pas par lexos-defaut"

if grep -qE 'x-scheme-handler|application/pdf|inode/directory|audio/mpeg' \
		"$BANC/moteur.py" "$BANC/page.js"; then
	non "des types MIME sont recopiés dans les Paramètres — deux sources"
else
	ok "aucun type MIME recopié dans les Paramètres ni dans la page"
fi

grep -q '"defaut-appli": act_defaut' "$BANC/moteur.py" \
	&& ok "le moteur connaît l'action « defaut-appli »" \
	|| non "l'action « defaut-appli » n'est pas dans la table ACTIONS"

#  ACTIONS est une table évaluée À L'IMPORT : une fonction définie plus bas
#  que la table donne un NameError au chargement du module, et les Paramètres
#  ne s'ouvrent plus du tout. C'est arrivé pendant l'écriture d'act_defaut.
LIG_ACT="$(grep -n '^def act_defaut' "$MOTEUR" | head -1 | cut -d: -f1)"
LIG_TAB="$(grep -n '^ACTIONS = {' "$MOTEUR" | head -1 | cut -d: -f1)"
if [ -n "$LIG_ACT" ] && [ -n "$LIG_TAB" ] && [ "$LIG_ACT" -lt "$LIG_TAB" ]; then
	ok "act_defaut est définie AVANT la table ACTIONS"
else
	non "act_defaut est définie après ACTIONS : le module ne s'importerait pas"
fi

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
