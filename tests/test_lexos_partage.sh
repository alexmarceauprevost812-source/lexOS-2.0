#!/usr/bin/env bash
# =============================================================================
#  Éprouver le PARTAGE — et le nom que les autres appareils voient
# =============================================================================
#  ALEX : « le contenu comme Ubuntu ». La page « Partage » d'Ubuntu commence
#  par le NOM DE L'ORDINATEUR, puis dit ce qui est partagé et comment. Ici, il
#  n'y avait qu'une ligne : « serveur actif » ou « au repos ».
#
#  DEUX DÉFAUTS, DONT UN QUI MENTAIT.
#
#  1. LexOS n'avait AUCUN moyen de changer le nom de la machine — ni fenêtre,
#     ni commande. Ce nom est pourtant celui que le téléphone affiche dans sa
#     liste d'appareils, celui du réseau, celui de l'invite du terminal.
#
#  2. « pgrep -f share-server.py » compare la ligne de commande ENTIÈRE de
#     chaque processus. N'importe quelle commande mentionnant ce nom — un
#     éditeur ouvert dessus, un grep, un banc d'essai — faisait dire
#     « partage actif » alors que rien ne tournait. Vu pour de vrai en
#     écrivant ce code : le premier « --json » a répondu « actif ».
#
#  ET LE PIÈGE DU RENOMMAGE, celui que personne ne voit venir : changer
#  /etc/hostname sans toucher à la ligne « 127.0.1.1 » de /etc/hosts laisse un
#  système où chaque sudo attend, puis affiche « unable to resolve host ». Le
#  symptôme n'a rien à voir avec le nom. Ce banc renomme une machine inventée
#  et relit les DEUX fichiers.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTIL="$RACINE/config/includes.chroot/usr/bin/lexos-share"
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

mkdir -p "$BANC/bin"
cat > "$BANC/bin/xfce4-terminal" <<'SH'
#!/bin/sh
for a in "$@"; do printf '%s\n' "$a"; done >> "${BANC_TRACE:?}"
printf -- '---\n' >> "$BANC_TRACE"
SH
chmod +x "$BANC/bin"/*
: > "$BANC/trace"
export BANC_TRACE="$BANC/trace"
CHEMIN="$BANC/bin:$RACINE/config/includes.chroot/usr/bin:$PATH"

# =============================================================================
titre "1. « --json » — ce que la page ne peut pas deviner"
# =============================================================================
if ! command -v python3 >/dev/null 2>&1; then
	saute "python3 absent : le JSON n'a PAS été éprouvé"
	ETAT=""
else
	ETAT="$(PATH="$CHEMIN" bash "$OUTIL" --json 2>/dev/null)"
	printf '%s' "$ETAT" > "$BANC/etat.json"
	if printf '%s' "$ETAT" | python3 -m json.tool >/dev/null 2>&1; then
		ok "« lexos-share --json » rend du JSON valide"
	else
		non "« --json » ne rend pas du JSON valide :\\n$ETAT"
		ETAT=""
	fi
fi

if [ -n "$ETAT" ]; then
	LU="$(python3 - "$BANC/etat.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
manque = [k for k in ("nom", "nom_regex", "actif", "recus", "minutes",
                      "kde", "bt", "qr", "ssh_serveur") if k not in d]
print("CHAMPS", "oui" if not manque else "NON:%s" % manque)
print("NOM", "oui" if d.get("nom") else "NON:vide")
print("BOOLS", "oui" if all(isinstance(d.get(k), bool)
                            for k in ("actif", "kde", "bt", "qr", "ssh_serveur"))
      else "NON")
print("REGEX", d.get("nom_regex", ""))
PY
)"
	case "$LU" in
		*"CHAMPS oui"*) ok "les neuf champs attendus sont publiés" ;;
		*) non "des champs manquent (${LU#*CHAMPS })" ;;
	esac
	case "$LU" in
		*"NOM oui"*) ok "le nom de la machine est publié" ;;
		*) non "le nom de la machine est vide" ;;
	esac
	case "$LU" in
		*"BOOLS oui"*) ok "les états sont de vrais booléens, pas des chaînes" ;;
		*) non "un état n'est pas un booléen : la page en ferait n'importe quoi" ;;
	esac
	case "$LU" in
		*'REGEX ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$'*)
			ok "la règle des noms de machine (RFC 1123) est publiée, pas devinée" ;;
		*) non "la règle des noms de machine n'est pas publiée telle quelle" ;;
	esac
fi

# =============================================================================
titre "2. « actif » NE DOIT PAS SE DÉCLENCHER SUR SON PROPRE NOM"
# =============================================================================
#  C'est le défaut mesuré : « pgrep -f share-server.py » se reconnaissait dans
#  n'importe quelle commande citant ce nom. On lance donc un processus qui le
#  cite SANS être le serveur, et on regarde ce que l'outil répond.
if ! command -v pgrep >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
	saute "pgrep ou python3 absent : le faux positif n'a PAS été éprouvé"
else
	#  « sleep » lancé avec un argument qui contient le nom du fichier : sa
	#  ligne de commande le cite, il n'est évidemment pas le serveur.
	(exec -a "cat share-server.py" sleep 5) &
	LEURRE=$!
	sleep 0.2
	ACT="$(PATH="$CHEMIN" bash "$OUTIL" --json 2>/dev/null \
		| python3 -c 'import json,sys; print(json.load(sys.stdin)["actif"])' 2>/dev/null)"
	kill "$LEURRE" 2>/dev/null
	wait "$LEURRE" 2>/dev/null
	[ "$ACT" = "False" ] \
		&& ok "un processus qui cite « share-server.py » ne fait plus dire « actif »" \
		|| non "le partage se dit actif ($ACT) à cause d'un processus qui cite son nom"
fi

# =============================================================================
titre "3. RENOMMER LA MACHINE — les DEUX fichiers, ou rien"
# =============================================================================
#  On fait tourner cmd_nom sur une machine inventée : son /etc/hostname et son
#  /etc/hosts, tous deux sous le décor. Écrire l'un sans l'autre laisse un
#  système où chaque sudo attend puis dit « unable to resolve host ».
mkdir -p "$BANC/etc"
printf 'ancien-poste\n' > "$BANC/etc/hostname"
cat > "$BANC/etc/hosts" <<'HOSTS'
127.0.0.1	localhost
127.0.1.1	ancien-poste
::1	localhost ip6-localhost ip6-loopback
HOSTS
#  ═══ LE DÉCOR PASSE PAR LE SEUIL DE L'OUTIL, PAS PAR UNE COPIE MODIFIÉE ═══
#  La première version de ce banc recopiait le script en remplaçant le chemin
#  de /etc/hosts par sed. Deux défauts, et le second est celui qui compte :
#
#    · on éprouvait une COPIE, pas le programme livré dans l'image ;
#    · renommer la machine exige root, et le coureur de la CI n'est pas root.
#      Toute cette section serait donc restée ROUGE là-bas — c'est-à-dire que
#      la partie la plus utile de ce code (la ligne 127.0.1.1 de /etc/hosts,
#      celle sans laquelle chaque sudo attend puis dit « unable to resolve
#      host ») n'aurait été éprouvée nulle part où ça compte.
#
#  lexos-share porte donc un seuil documenté, LEXOS_HOSTNAME_RACINE, sur le
#  modèle de LEXOS_BIENETRE_DIR et LEXOS_NUAGE : il déplace /etc/hostname ET
#  /etc/hosts sous un dossier à part, et n'exige plus root puisqu'il n'y a
#  plus rien de partagé à écrire.
export LEXOS_HOSTNAME_RACINE="$BANC"
if [ "$(LEXOS_HOSTNAME_RACINE="$BANC" bash "$OUTIL" --json 2>/dev/null \
        | sed -n 's/.*"nom": "\([^"]*\)".*/\1/p')" = "ancien-poste" ]; then
	ok "le seuil du banc détourne bien /etc/hostname et /etc/hosts vers son décor"
	SORTIE="$(PATH="$BANC/bin:$PATH" bash "$OUTIL" nom nouveau-poste 2>&1)"
	CODE=$?
	NOM_APRES="$(cat "$BANC/etc/hostname")"
	[ "$NOM_APRES" = "nouveau-poste" ] \
		&& ok "le nom de la machine a changé (« $NOM_APRES »)" \
		|| non "le nom n'a pas changé : « $NOM_APRES »"
	if grep -q '^127\.0\.1\.1[[:space:]]*nouveau-poste$' "$BANC/etc/hosts"; then
		ok "la ligne 127.0.1.1 de /etc/hosts suit le nouveau nom"
	else
		non "127.0.1.1 est resté sur l'ancien nom : chaque sudo attendra puis dira « unable to resolve host »"
	fi
	grep -q '^127\.0\.0\.1[[:space:]]*localhost$' "$BANC/etc/hosts" \
		&& ok "les autres lignes de /etc/hosts sont intactes" \
		|| non "/etc/hosts a perdu des lignes en route"
	[ -e "$BANC/etc/hosts.lexos-avant" ] \
		&& ok "une sauvegarde de /etc/hosts est posée avant la première modification" \
		|| non "aucune sauvegarde de /etc/hosts"
	[ "$CODE" = 0 ] || non "la commande a rendu $CODE : $SORTIE"

	#  ═══ UN /etc/hosts SANS LIGNE 127.0.1.1 ═══ Debian en pose une, mais pas
	#  toutes les images : si elle manque, il faut l'AJOUTER, pas abandonner.
	printf '127.0.0.1\tlocalhost\n' > "$BANC/etc/hosts"
	rm -f "$BANC/etc/hosts.lexos-avant"
	PATH="$BANC/bin:$PATH" bash "$OUTIL" nom autre-poste >/dev/null 2>&1
	grep -q '^127\.0\.1\.1[[:space:]]*autre-poste$' "$BANC/etc/hosts" \
		&& ok "si la ligne 127.0.1.1 manque, elle est ajoutée" \
		|| non "aucune ligne 127.0.1.1 ajoutée : le nom ne se résoudra pas"

	#  ═══ LES NOMS REFUSÉS ═══ avant d'avoir rien écrit.
	for MAUVAIS in "-poste" "poste-" "un poste" "poste_2" "" ; do
		AVANT="$(cat "$BANC/etc/hostname")"
		PATH="$BANC/bin:$PATH" bash "$OUTIL" nom "$MAUVAIS" >/dev/null 2>&1
		[ "$(cat "$BANC/etc/hostname")" = "$AVANT" ] \
			&& ok "refusé sans rien écrire : « ${MAUVAIS:-（vide）} »" \
			|| non "« $MAUVAIS » a été accepté comme nom de machine"
	done
else
	non "le seuil du banc n'a pas pris — contrôle non joué (jamais sur le vrai /etc)"
fi

# =============================================================================
titre "4. LE GESTE DEPUIS LA PAGE — la commande exacte"
# =============================================================================
if ! command -v python3 >/dev/null 2>&1; then
	saute "python3 absent : le geste n'a PAS été éprouvé"
else
	cat > "$BANC/geste.py" <<'PY'
import sys, time
sys.path.insert(0, sys.argv[1])
import settings

trace = sys.argv[2]

try:
    def lire():
        try:
            return open(trace, encoding="utf-8").read()
        except OSError:
            return ""

    def derniere():
        blocs = [b for b in lire().split("---\n") if b.strip()]
        if not blocs:
            return ""
        for l in blocs[-1].splitlines():
            if l.startswith("sudo "):
                return l
        return ""

    def geste(arg):
        #  _terminal() lance la fenêtre en detach=True : Popen rend la main
        #  avant que la doublure ait écrit. On attend que le fichier bouge.
        avant = lire()
        r = settings.act_partage(arg)
        if r.get("ok"):
            for _ in range(200):
                m = lire()
                if m != avant and m.endswith("---\n"):
                    break
                time.sleep(0.01)
        return r, derniere()

    r, cmd = geste("nom:poste-du-banc")
    print(("OK|" if (r.get("ok") and
                     cmd == "sudo lexos-share nom poste-du-banc; bash") else "NON|") +
          "renommer → %s" % (cmd or r.get("erreur", "AUCUNE FENÊTRE")))

    courant = settings._partage_etat().get("nom", "")
    for arg, bout, quoi in (
            ("nom:-poste",        "nom de machine invalide", "un nom qui commence par un tiret"),
            ("nom:un poste",      "nom de machine invalide", "un nom avec une espace"),
            ("nom:poste;reboot",  "nom de machine invalide", "une commande glissée dans le nom"),
            ("nom:poste\n",       "nom de machine invalide", "un nom suivi d'un retour à la ligne"),
            ("nom:",              "il faut un nom",          "aucun nom"),
            ("truc:poste",        "geste inattendu",         "un geste inventé"),
            ("nom:" + courant,    "s'appelle déjà",          "le nom qu'elle porte déjà")):
        avant = derniere()
        r, cmd = geste(arg)
        print(("OK|" if (not r.get("ok") and bout in r.get("erreur", "") and cmd == avant)
               else "NON|") +
              "refusé sans ouvrir de fenêtre : %s (%s)" % (quoi, r.get("erreur", "ACCEPTÉ !")))
except Exception as _e:
    print("NON|le banc s'est arrêté : %s: %s" % (type(_e).__name__, _e))
print("FIN|")
PY
	SORTIE_G="$(cd "$RACINE" && PATH="$CHEMIN" \
		python3 "$BANC/geste.py" \
		"$RACINE/config/includes.chroot/usr/lib/lexos" "$BANC/trace" 2>/dev/null \
		| grep -E '^(OK|NON|FIN)\|' || true)"
	if [ -z "$SORTIE_G" ]; then
		non "le geste n'a rien rendu — le moteur n'a pas pu être appelé"
	elif ! grep -q '^FIN|' <<< "$SORTIE_G"; then
		non "le banc s'est arrêté avant la fin — des contrôles n'ont jamais tourné"
	else
		while IFS='|' read -r V M; do
			case "$V" in OK) ok "$M" ;; NON) non "$M" ;; esac
		done <<EOF
$SORTIE_G
EOF
	fi
fi

# =============================================================================
titre "5. LA PAGE — ce qu'elle montre, et ce qu'elle avoue"
# =============================================================================
if ! command -v node >/dev/null 2>&1; then
	saute "node absent : la page n'a PAS été rendue"
else
	cat > "$BANC/rendu.js" <<'JS'
"use strict";
const fs = require("fs"), vm = require("vm");
const source = fs.readFileSync(process.argv[2], "utf8")
  + "\n;globalThis.__banc = { contenu, pose: e => { etat = e; } };\n";
const el = () => ({ innerHTML:"", textContent:"", hidden:true, style:{}, dataset:{},
                    classList:{add(){},remove(){},toggle(){}},
                    querySelectorAll:()=>[], appendChild(){}, focus(){} });
const bac = vm.createContext({
  document:{ getElementById:()=>el(), querySelectorAll:()=>[], body:el(),
             documentElement:{style:{setProperty(){}},dataset:{}}, addEventListener(){} },
  location:{hash:""}, window:{confirm:()=>true},
  fetch:()=>Promise.reject(new Error("pas de pont")),
  requestAnimationFrame:()=>0, setTimeout, clearTimeout, console });
bac.globalThis = bac;
vm.runInContext(source, bac, {filename:"app.js"});
const T = bac.__banc;
const dit = (bon, m) => console.log((bon ? "OK|" : "NON|") + m);
try {
  const tout = {dispo:true, nom:'poste-"salon"', nom_regex:"^x$", actif:true,
    recus:"/home/alex/LexOS-reçus", minutes:15,
    kde:true, bt:true, qr:true, ssh_serveur:true};
  T.pose({partage: tout});
  let h = T.contenu("partage");
  dit(h.includes('id="partageNom"') && h.includes("setNomMachine()"),
      "le nom de la machine se change depuis la page");
  dit(!/poste-"salon"/.test(h) && h.includes("poste-&quot;salon&quot;"),
      "un nom à guillemets est échappé dans le HTML");
  dit(h.includes("15 minutes"), "quand le serveur tourne, la page dit quand il s'arrête");
  dit(h.includes("LexOS-reçus"), "la page dit où arrivent les fichiers reçus");
  dit((h.match(/>prêt</g) || []).length === 3,
      "les trois moyens présents sont annoncés prêts");
  dit(!h.includes("openssh-server"),
      "avec un serveur SSH installé, on ne propose pas de l'installer");

  //  RIEN N'EST LÀ : c'est le rendu qui compte, parce qu'un moyen absent
  //  présenté comme disponible envoie cliquer dans le vide.
  const rien = Object.assign({}, tout, {kde:false, bt:false, qr:false,
                                        ssh_serveur:false, actif:false});
  T.pose({partage: rien});
  h = T.contenu("partage");
  dit((h.match(/>absent</g) || []).length === 3,
      "les trois moyens manquants sont annoncés absents");
  dit(h.includes("kdeconnect-cli n'est pas installé") &&
      h.includes("bluetoothctl n'est pas installé"),
      "et la page NOMME ce qui manque, au lieu de dire « absent » tout court");
  dit(h.includes("openssh-server"),
      "sans serveur SSH, la page dit comment en installer un");
  dit(h.includes("au repos"), "le serveur arrêté est dit au repos");

  T.pose({partage: {}});
  dit(T.contenu("partage").includes("lexos-share n'a pas répondu"),
      "si l'outil ne répond pas, la page le dit au lieu de rester blanche");
} catch (e) {
  console.log("NON|le rendu s'est arrêté : " + (e && e.message || e));
}
console.log("FIN|");
JS
	SORTIE_P="$(node "$BANC/rendu.js" "$PAGE" 2>&1 | grep -E '^(OK|NON|FIN)\|' || true)"
	if [ -z "$SORTIE_P" ]; then
		non "la page n'a rien rendu — app.js n'a pas pu être chargé"
	elif ! grep -q '^FIN|' <<< "$SORTIE_P"; then
		non "le rendu s'est arrêté avant la fin — des contrôles n'ont jamais tourné"
	else
		while IFS='|' read -r V M; do
			case "$V" in OK) ok "$M" ;; NON) non "$M" ;; esac
		done <<EOF
$SORTIE_P
EOF
	fi
fi

# =============================================================================
titre "6. UNE SEULE SOURCE"
# =============================================================================
sed 's|#.*$||' "$MOTEUR" > "$BANC/moteur.py"
grep -q 'lexos-share' "$BANC/moteur.py" \
	&& ok "le moteur demande son état à lexos-share" \
	|| non "le moteur ne passe pas par lexos-share"
#  ON CHERCHE LA FORME DU CODE, pas le mot. « sed 's|#.*$||' » retire les
#  commentaires, pas les docstrings — et l'explication de _partage_etat() cite
#  justement « share-server.py » pour raconter le défaut corrigé. Un contrôle
#  qui chercherait le mot serait rouge à cause du texte qui explique le
#  correctif : le pire des faux positifs, celui qui apprend à ignorer les rouges.
if grep -q '"share-server\.py"' "$BANC/moteur.py"; then
	non "le moteur cherche encore le serveur lui-même — deux façons de répondre à la même question"
else
	ok "le moteur ne cherche plus le serveur de son côté"
fi
grep -q '"partage-nom": act_partage' "$BANC/moteur.py" \
	&& ok "le moteur connaît l'action « partage-nom »" \
	|| non "l'action « partage-nom » n'est pas dans la table ACTIONS"
LIG_ACT="$(grep -n '^def act_partage' "$MOTEUR" | head -1 | cut -d: -f1)"
LIG_TAB="$(grep -n '^ACTIONS = {' "$MOTEUR" | head -1 | cut -d: -f1)"
if [ -n "$LIG_ACT" ] && [ -n "$LIG_TAB" ] && [ "$LIG_ACT" -lt "$LIG_TAB" ]; then
	ok "act_partage est définie AVANT la table ACTIONS"
else
	non "act_partage est définie après ACTIONS : le module ne s'importerait pas"
fi

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
