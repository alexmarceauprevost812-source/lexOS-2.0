#!/usr/bin/env bash
# =============================================================================
#  Éprouver les QUATRE pages qui ne servaient qu'à regarder
# =============================================================================
#  ALEX : « fais en sorte qu'il soit tout comme Ubuntu 26.04.01 », puis « le
#  contenu comme Ubuntu », puis « là tu fais tous les paramètres ».
#
#  Un inventaire mesuré — chaque section rendue pour de vrai, et ses boutons
#  comptés — a nommé les pages qui n'avaient AUCUN réglage. Quatre d'entre
#  elles n'avaient aucune excuse matérielle : elles listaient des commandes à
#  taper dans un terminal, pour des réglages qui ne demandent rien de plus
#  qu'un clic.
#
#    Terminal jour/nuit ... quatre commandes recopiées, et pas même l'état
#    Bien-être numérique .. trois lignes de compteurs, zéro interrupteur
#    Comptes en ligne ..... la liste des comptes, sans dire lesquels sont OUVERTS
#    Recherche ............ une phrase vraie, mais aucune recherche
#
#  ELLES SE RESSEMBLENT TOUTES LES QUATRE, ET C'EST POURQUOI ELLES SONT DANS
#  LE MÊME BANC : un outil LexOS qui sait déjà tout faire, un « --json » qui
#  publie son état, un geste dans le moteur qui refuse avant d'agir, une page
#  qui montre ce que l'outil dit. On n'a réécrit aucune logique d'outil.
#
#  CE QUE CE BANC SURVEILLE EN PARTICULIER : les gestes qui DÉTRUISENT ou qui
#  ATTENDENT UNE RÉPONSE doivent passer par un terminal. « lexos-bienetre
#  oublier » fait taper le mot « effacer » ; lancé sans terminal, ce « read »
#  échoue, l'outil répond « Annulé. » et rend 0 — le moteur aurait annoncé un
#  succès pour une suppression qui n'a pas eu lieu.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$RACINE/config/includes.chroot/usr/bin"
MOTEUR="$RACINE/config/includes.chroot/usr/lib/lexos/settings.py"
PAGE="$RACINE/config/includes.chroot/usr/share/lexos/settings/web/app.js"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
saute(){ printf '  \033[33m•\033[0m %s\n' "$1"; }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

for F in "$MOTEUR" "$PAGE" "$BIN/lexos-terminal" "$BIN/lexos-bienetre" \
         "$BIN/lexos-comptes" "$BIN/lexos-recherche"; do
	[ -r "$F" ] || { echo "introuvable : $F"; exit 1; }
done

mkdir -p "$BANC/bin" "$BANC/foyer"
cat > "$BANC/bin/xfce4-terminal" <<'SH'
#!/bin/sh
for a in "$@"; do printf '%s\n' "$a"; done >> "${BANC_TRACE:?}"
printf -- '---\n' >> "$BANC_TRACE"
SH
#  UNE DOUBLURE DE rclone, ET C'EST INDISPENSABLE. Sans elle, le décor
#  dépendrait de ce qui est installé sur la machine qui fait tourner le banc :
#  ici rclone est absent, donc « relier un compte » était refusé avant même
#  d'arriver au contrôle qu'on voulait éprouver — et le banc annonçait un
#  rouge qui ne parlait pas du code. Les comptes eux-mêmes viennent de
#  LEXOS_RCLONE_REMOTES, qui a la priorité : cette doublure n'a qu'à exister.
#  ═══ ET UNE DOUBLURE DE plocate ═══
#  « Par nom » lit un index, et l'outil refuse d'abord si le BINAIRE plocate
#  manque. Sur le coureur de la CI, il manque — le contrôle « avec un index,
#  la recherche par nom part » tombait donc sur ce refus-là, pas sur celui
#  qu'il éprouve. Vert ici, rouge là-bas : le même défaut que /etc/lightdm,
#  refait le jour même. Le décor fournit donc le binaire, et l'index reste
#  gouverné par LEXOS_PLOCATE_DB.
cat > "$BANC/bin/plocate" <<'SH'
#!/bin/sh
exit 0
SH

cat > "$BANC/bin/rclone" <<'SH'
#!/bin/sh
case "$1" in
  listremotes) cat "${LEXOS_RCLONE_REMOTES:-/dev/null}" ;;
  version)     printf 'rclone v1.0-banc
' ;;
  *)           exit 0 ;;
esac
SH
chmod +x "$BANC/bin"/*
: > "$BANC/trace"
export BANC_TRACE="$BANC/trace"
CHEMIN="$BANC/bin:$BIN:$PATH"

#  Les quatre outils écrivent dans le dossier de la personne connectée. Un
#  HOME jetable, donc : le banc ne doit rien changer chez qui le lance.
export HOME="$BANC/foyer"
printf 'drive-alex:\nphotos:\n' > "$BANC/remotes"
export LEXOS_RCLONE_REMOTES="$BANC/remotes"

#  ═══ L'INDEX DE plocate EST CELUI DU DÉCOR, PAS CELUI DE LA MACHINE ═══
#  Ce banc vérifie qu'une recherche par NOM est refusée faute d'index. Il
#  lisait le vrai /var/lib/plocate/plocate.db : vert sur une machine sans
#  plocate, ROUGE dès qu'un updatedb passait. C'est arrivé au milieu d'une
#  session — le banc est devenu rouge sans qu'une ligne de code ait bougé, et
#  la CI serait tombée à la poussée suivante. Un banc qui mesure la machine
#  n'éprouve pas le dépôt.
export LEXOS_PLOCATE_DB="$BANC/pas-d-index"

# =============================================================================
titre "1. Les quatre « --json » — chacun publie ce que sa page ne peut pas deviner"
# =============================================================================
if ! command -v python3 >/dev/null 2>&1; then
	saute "python3 absent : les sorties JSON n'ont PAS été éprouvées"
else
	for COUPLE in "lexos-terminal:mode,effectif,debut,fin,minuterie" \
	              "lexos-bienetre:tourne,minutes,limite,pauses_installe,nuit_installe,semaine" \
	              "lexos-comptes:rclone,gvfs,nuage,comptes,services" \
	              "lexos-recherche:plocate,index,index_jours,catfish,max"; do
		OUTIL="${COUPLE%%:*}"; CLES="${COUPLE#*:}"
		SORTIE="$(PATH="$CHEMIN" bash "$BIN/$OUTIL" --json 2>/dev/null)"
		printf '%s' "$SORTIE" > "$BANC/$OUTIL.json"
		if ! printf '%s' "$SORTIE" | python3 -m json.tool >/dev/null 2>&1; then
			non "« $OUTIL --json » ne rend pas du JSON valide"
			continue
		fi
		MANQUE="$(python3 - "$BANC/$OUTIL.json" "$CLES" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
print(",".join(k for k in sys.argv[2].split(",") if k not in d))
PY
)"
		[ -z "$MANQUE" ] \
			&& ok "« $OUTIL --json » rend du JSON valide, avec ses clés" \
			|| non "« $OUTIL --json » : clés manquantes ($MANQUE)"
	done

	#  LA SEMAINE DU BIEN-ÊTRE : sept jours, pas six ni huit. Sept nombres,
	#  c'est ce qui transforme un compteur en information.
	N="$(python3 -c '
import json, sys
print(len(json.load(open(sys.argv[1], encoding="utf-8")).get("semaine", [])))
' "$BANC/lexos-bienetre.json" 2>/dev/null)"
	[ "${N:-0}" = "7" ] \
		&& ok "le bien-être publie les sept derniers jours" \
		|| non "la semaine ne fait pas sept jours (${N:-?})"

	#  LES COMPTES : le catalogue des services vient de l'outil, avec le type
	#  rclone EXACT — celui qui fait la différence entre une commande qui
	#  marche et un « unknown remote type ».
	LU="$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
s = {x["cle"]: x["type"] for x in d.get("services", [])}
print(len(s), s.get("google", ""), s.get("nextcloud", ""))
' "$BANC/lexos-comptes.json" 2>/dev/null)"
	read -r NS TG TN <<< "${LU:-0 x x}"
	[ "${NS:-0}" -ge 8 ] && [ "$TG" = "drive" ] && [ "$TN" = "webdav" ] \
		&& ok "le catalogue des services publie le type rclone exact ($NS services)" \
		|| non "le catalogue des services est incomplet ou faux ($LU)"

	#  ET LES DEUX COMPTES DU DÉCOR SONT VUS, NON MONTÉS.
	LU="$(python3 -c '
import json, sys
c = json.load(open(sys.argv[1], encoding="utf-8")).get("comptes", [])
print(",".join(x["nom"] for x in c), any(x["monte"] for x in c))
' "$BANC/lexos-comptes.json" 2>/dev/null)"
	case "$LU" in
		"drive-alex,photos False") ok "les comptes reliés sont lus, et aucun n'est dit ouvert à tort" ;;
		*) non "les comptes reliés ne sont pas ceux du décor ($LU)" ;;
	esac
fi

# =============================================================================
titre "2. LES GESTES — ce qui agit, ce qui ouvre un terminal, ce qui refuse"
# =============================================================================
if ! command -v python3 >/dev/null 2>&1; then
	saute "python3 absent : les gestes n'ont PAS été éprouvés"
else
	cat > "$BANC/gestes.py" <<'PY'
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
        lignes = [l for l in blocs[-1].splitlines() if not l.startswith("--")]
        return lignes[-1] if lignes else ""

    def geste(action, arg):
        """L'action, PUIS ce qui est parti dans le terminal — s'il y en a un.

        _terminal() lance la fenêtre en detach=True : Popen rend la main avant
        que la doublure ait écrit. On attend que le fichier bouge, avec une
        limite — un geste qui n'ouvre pas de fenêtre n'écrira jamais.
        """
        avant = lire()
        r = settings.ACTIONS[action](arg)
        for _ in range(60):
            m = lire()
            if m != avant and m.endswith("---\n"):
                break
            time.sleep(0.01)
        return r, derniere(), lire() != avant

    #  ═══ CE QUI DOIT PASSER PAR UN TERMINAL ═══
    #  Ces trois-là posent une question ou détruisent quelque chose. Lancés
    #  sans terminal, ils échouent EN SILENCE : « lexos-bienetre oublier »
    #  fait taper le mot « effacer », et sans réponse il dit « Annulé. » puis
    #  rend 0. Le moteur aurait annoncé un succès pour une suppression qui
    #  n'a pas eu lieu — le mensonge le plus coûteux d'une page de réglages.
    for action, arg, attendue, quoi in (
            ("bienetre", "oublier:",
             "lexos-bienetre oublier; bash",
             "effacer l'historique (il fait taper « effacer »)"),
            ("comptes", "ajouter:google",
             "lexos-comptes ajouter google; bash",
             "relier un compte (rclone pose ses questions)"),
            ("comptes", "retirer:photos",
             "lexos-comptes retirer photos; bash",
             "retirer un compte (confirmation exigée)"),
            ("recherche", "contenu:impots",
             "lexos-recherche contenu impots; bash",
             "chercher dans le contenu (des dizaines de lignes)"),
            ("recherche", "doublons:",
             "lexos-recherche doublons; bash",
             "chercher les doublons")):
        r, cmd, fenetre = geste(action, arg)
        print(("OK|" if (r.get("ok") and fenetre and cmd == attendue) else "NON|") +
              "terminal : %s → %s" % (quoi, cmd or r.get("erreur", "AUCUNE FENÊTRE")))

    #  ═══ ET LE MOT CHERCHÉ EST CITÉ ═══ c'est du texte libre.
    r, cmd, _ = geste("recherche", "contenu:un ; rm -rf / 'x'")
    print(("OK|" if (r.get("ok") and
                     cmd == "lexos-recherche contenu 'un ; rm -rf / '\"'\"'x'\"'\"''; bash")
           else "NON|") +
          "un mot cherché piégé ressort en UN argument cité (%s)" % cmd)

    #  ═══ CE QUI NE DOIT PAS OUVRIR DE FENÊTRE ═══
    #  Ces gestes-là n'ont rien à demander : ils agissent, ou ils refusent.
    for action, arg, quoi in (
            ("terminal-mode", "mode:nuit", "changer le mode du terminal"),
            ("terminal-mode", "horaire:08:00-20:00", "changer les heures du jour"),
            ("bienetre", "limite:120", "poser une limite")):
        r, _, fenetre = geste(action, arg)
        print(("OK|" if (r.get("ok") and not fenetre) else "NON|") +
              "sans terminal : %s (%s)" % (quoi, r.get("erreur", "fait")))

    #  ═══ ET CE QUI A VRAIMENT CHANGÉ ═══ on relit l'état, on ne croit pas
    #  sur parole le code de retour.
    t = settings._terminal_etat()
    print(("OK|" if t.get("mode") == "nuit" else "NON|") +
          "le mode du terminal est bien « nuit » (%s)" % t.get("mode"))
    settings.ACTIONS["terminal-mode"]("mode:auto")
    t = settings._terminal_etat()
    print(("OK|" if (t.get("debut") == "08:00" and t.get("fin") == "20:00") else "NON|") +
          "les heures du jour sont bien 08:00–20:00 (%s–%s)" % (t.get("debut"), t.get("fin")))
    b = settings._bienetre_etat()
    print(("OK|" if b.get("limite") == 120 else "NON|") +
          "la limite du jour est bien 120 minutes (%s)" % b.get("limite"))
    settings.ACTIONS["bienetre"]("limite:off")
    print(("OK|" if settings._bienetre_etat().get("limite") == 0 else "NON|") +
          "et « off » la retire")

    #  ═══ CE QUI DOIT ÊTRE REFUSÉ, AVANT D'AGIR ═══
    for action, arg, bout, quoi in (
            ("terminal-mode", "mode:violet",      "mode inattendu",     "un mode de terminal inventé"),
            ("terminal-mode", "horaire:8h-20h",   "format HH:MM",       "des heures mal écrites"),
            ("terminal-mode", "horaire:25:00-08:00", "format HH:MM",    "une heure qui n'existe pas"),
            ("terminal-mode", "horaire:08:00-08:00", "même heure",      "un jour de durée nulle"),
            ("terminal-mode", "truc:x",           "geste inattendu",    "un geste inventé"),
            ("bienetre",      "limite:0",         "entre 1 et 1440",    "une limite de zéro"),
            ("bienetre",      "limite:abc",       "entre 1 et 1440",    "une limite qui n'est pas un nombre"),
            ("bienetre",      "limite:99999",     "entre 1 et 1440",    "une limite de 69 jours"),
            ("bienetre",      "compteur:peut-etre", "« on » ou « off »", "un interrupteur à trois positions"),
            #  ON EXIGE LE MOTIF DU MOTEUR, PAS CELUI DE L'OUTIL.
            #  lexos-bienetre refuse aussi d'allumer un programme absent, et
            #  avec presque les mêmes mots — « workrave n'est pas installé. ».
            #  Un contrôle qui se contenterait de ces mots-là serait donc VERT
            #  même si le moteur ne vérifiait plus rien : mesuré, la mutation
            #  est passée inaperçue à la première écriture de ce banc. C'est
            #  la faute exacte déjà corrigée au banc du clavier, refaite ici.
            #  Ce qui distingue les deux messages, c'est la commande qui
            #  RÉPARE — et c'est justement l'information utile.
            ("bienetre",      "pauses:on",        "lexos install workrave", "allumer un programme absent"),
            ("bienetre",      "nuit:on",          "lexos install redshift", "allumer l'autre programme absent"),
            ("comptes",       "monter:inconnu",   "n'est pas un compte relié", "monter un compte qui n'existe pas"),
            ("comptes",       "ajouter:pigeon",   "n'est pas un service connu", "un service inventé"),
            ("comptes",       "demonter:photos",  "n'est pas ouvert",   "refermer un compte déjà fermé"),
            ("recherche",     "contenu:",         "il faut un mot",     "une recherche sans mot"),
            ("recherche",     "nom:rapport",      "index",              "la recherche par nom sans index"),
            ("recherche",     "truc:x",           "geste inattendu",    "un geste de recherche inventé")):
        avant = derniere()
        r, cmd, fenetre = geste(action, arg)
        print(("OK|" if (not r.get("ok") and bout in r.get("erreur", "") and not fenetre)
               else "NON|") +
              "refusé sans rien lancer : %s (%s)" % (quoi, r.get("erreur", "ACCEPTÉ !")))

    #  ═══ ET L'AUTRE SENS : AVEC UN INDEX, ÇA DOIT PASSER ═══
    #  Un refus permanent est un défaut aussi, et c'est le plus facile à
    #  écrire sans s'en apercevoir. Sans ce contrôle, une recherche par nom
    #  cassée pour toujours resterait verte.
    import os, pathlib
    db = pathlib.Path(os.environ["LEXOS_PLOCATE_DB"])
    db.write_text("faux index", encoding="utf-8")
    try:
        r, cmd, fenetre = geste("recherche", "nom:rapport")
        print(("OK|" if (r.get("ok") and fenetre and
                         cmd == "lexos-recherche nom rapport; bash") else "NON|") +
              "avec un index, la recherche par nom part (%s)"
              % (cmd or r.get("erreur", "REFUSÉE")))
    finally:
        db.unlink(missing_ok=True)
except Exception as _e:
    print("NON|le banc s'est arrêté : %s: %s" % (type(_e).__name__, _e))
print("FIN|")
PY
	SORTIE_G="$(cd "$RACINE" && PATH="$CHEMIN" HOME="$BANC/foyer" \
		LEXOS_RCLONE_REMOTES="$BANC/remotes" \
		python3 "$BANC/gestes.py" \
		"$RACINE/config/includes.chroot/usr/lib/lexos" "$BANC/trace" 2>/dev/null \
		| grep -E '^(OK|NON|FIN)\|' || true)"
	if [ -z "$SORTIE_G" ]; then
		non "les gestes n'ont rien rendu — le moteur n'a pas pu être appelé"
	elif ! grep -q '^FIN|' <<< "$SORTIE_G"; then
		non "le banc s'est arrêté avant la fin — des contrôles n'ont jamais tourné"
		while IFS='|' read -r V M; do
			[ "$V" = "NON" ] && non "$M"
		done <<EOF
$SORTIE_G
EOF
	else
		while IFS='|' read -r V M; do
			case "$V" in OK) ok "$M" ;; NON) non "$M" ;; esac
		done <<EOF
$SORTIE_G
EOF
	fi
fi

# =============================================================================
titre "3. LES QUATRE PAGES — rendues sur des états qu'on a choisis"
# =============================================================================
if ! command -v node >/dev/null 2>&1; then
	saute "node absent : les pages n'ont PAS été rendues"
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
  /* ── TERMINAL ────────────────────────────────────────────────────────── */
  T.pose({terminal:{dispo:true, mode:"auto", effectif:"nuit", bureau:"sombre",
                    debut:"07:00", fin:"19:00", minuterie:false}});
  let h = T.contenu("terminal");
  dit(h.includes("setTerminalMode('jour')") && h.includes("setTerminalMode('nuit')") &&
      h.includes("setTerminalMode('auto')") && h.includes("setTerminalMode('suivre')"),
      "terminal : les quatre modes sont cliquables");
  dit(h.includes('id="termDebut"') && h.includes("setTerminalHoraire()"),
      "terminal : en mode « auto », les heures du jour se règlent");
  dit(h.includes("La minuterie n'est"),
      "terminal : sans minuterie armée, la page le dit au lieu de laisser attendre");
  //  L'ÉCART ENTRE LE MODE CHOISI ET LA COULEUR DU MOMENT est l'explication.
  dit(h.includes(">nuit<") && h.includes("07:00"),
      "terminal : le mode choisi ET la couleur du moment sont montrés");
  T.pose({terminal:{dispo:true, mode:"suivre", effectif:"jour", bureau:"clair",
                    debut:"07:00", fin:"19:00", minuterie:false}});
  h = T.contenu("terminal");
  dit(!h.includes('id="termDebut"'),
      "terminal : hors « auto », les heures du jour ne sont pas proposées");
  dit(h.includes("clair"), "terminal : en « suivre », la page dit ce que suit le terminal");
  T.pose({terminal:{}});
  dit(T.contenu("terminal").includes("lexos-terminal n'a pas répondu"),
      "terminal : outil muet, la page le dit");

  /* ── BIEN-ÊTRE ───────────────────────────────────────────────────────── */
  const be = {dispo:true, tourne:true, minutes:200, limite:180,
              pauses_installe:true, pauses_actif:false,
              nuit_installe:false, nuit_actif:false,
              semaine:[{jour:"2026-01-01",nom:"lun",minutes:60},
                       {jour:"2026-01-02",nom:"mar",minutes:120}],
              total_semaine:180};
  T.pose({bienetre: be});
  h = T.contenu("bienetre");
  dit(h.includes("setBienetre('compteur', false)"),
      "bien-être : le compteur en marche propose de l'arrêter");
  dit(h.includes("dépassée de"),
      "bien-être : une limite dépassée est annoncée comme telle");
  dit(h.includes("setBienetre('pauses'"),
      "bien-être : workrave installé donne un vrai interrupteur");
  dit(!h.includes("setBienetre('nuit'") && h.includes("redshift n'est pas installé"),
      "bien-être : redshift absent ne donne PAS d'interrupteur, mais la commande pour l'installer");
  dit(h.includes("setBienetreLimite()") && h.includes("oublierBienetre()"),
      "bien-être : la limite se change et l'historique s'efface depuis la page");
  //  « ZÉRO MINUTE » N'EST PAS « LE COMPTEUR EST ARRÊTÉ ».
  T.pose({bienetre: Object.assign({}, be, {tourne:false, minutes:0})});
  h = T.contenu("bienetre");
  dit(h.includes("ce n'est pas « zéro »"),
      "bien-être : compteur arrêté, la page refuse de faire croire à « 0 h 00 »");
  dit(h.includes("setBienetre('compteur', true)"),
      "bien-être : et propose de le démarrer");
  T.pose({bienetre:{}});
  dit(T.contenu("bienetre").includes("lexos-bienetre n'a pas répondu"),
      "bien-être : outil muet, la page le dit");

  /* ── COMPTES ─────────────────────────────────────────────────────────── */
  T.pose({comptes:{dispo:true, rclone:true, gvfs:true, nuage:"/home/alex/Nuage",
    comptes:[{nom:"drive-alex", monte:true},{nom:"photos", monte:false}],
    services:[{cle:"google", type:"drive", nom:"Google Drive", note:""}]}});
  h = T.contenu("comptes");
  dit(h.includes("setCompte('demonter','drive-alex')") &&
      h.includes("setCompte('monter','photos')"),
      "comptes : ouvert propose « Refermer », fermé propose « Ouvrir »");
  dit(h.includes("ses fichiers ne sont pas sur cette machine"),
      "comptes : un compte configuré mais fermé le DIT — c'est ce qui manquait");
  dit(h.includes("setCompte('ajouter', this.value)"),
      "comptes : on peut en relier un depuis la page");
  T.pose({comptes:{dispo:true, rclone:false, gvfs:false, nuage:"", comptes:[], services:[]}});
  h = T.contenu("comptes");
  dit(!h.includes("setCompte('ajouter'") && h.includes("lexos install rclone"),
      "comptes : sans rclone, on ne propose pas de relier — on dit comment l'installer");
  T.pose({comptes:{}});
  dit(T.contenu("comptes").includes("lexos-comptes n'a pas répondu"),
      "comptes : outil muet, la page le dit");

  /* ── RECHERCHE ───────────────────────────────────────────────────────── */
  T.pose({recherche:{dispo:true, plocate:true, index:true, index_jours:20,
                     catfish:true, max:30}});
  h = T.contenu("recherche");
  dit(h.includes("lancerRecherche('nom')") && h.includes("lancerRecherche('contenu')") &&
      h.includes("lancerRecherche('gros')") && h.includes("lancerRecherche('doublons')"),
      "recherche : on peut chercher depuis la page");
  dit(h.includes("vieux de 20 jours"),
      "recherche : l'ÂGE de l'index est dit — un index vieux ne trouve pas le fichier d'hier");
  dit(h.includes("lancerRecherche('fenetre')"),
      "recherche : catfish installé donne le bouton « Fenêtre »");
  T.pose({recherche:{dispo:true, plocate:false, index:false, index_jours:-1,
                     catfish:false, max:30}});
  h = T.contenu("recherche");
  dit(h.includes("la recherche par nom ne peut pas fonctionner") &&
      h.includes("lexos install plocate"),
      "recherche : sans plocate, la page dit que la recherche par nom ne marche pas");
  dit(!h.includes("lancerRecherche('fenetre')"),
      "recherche : sans catfish, pas de bouton « Fenêtre »");
  T.pose({recherche:{}});
  dit(T.contenu("recherche").includes("lexos-recherche n'a pas répondu"),
      "recherche : outil muet, la page le dit");

  /* ── APPLICATIONS ────────────────────────────────────────────────────── */
  T.pose({});
  h = T.contenu("applications");
  dit(h.includes("allerA('defaut')"),
      "applications : la page RENVOIE aux applications par défaut au lieu de les refaire");
  dit(!h.includes("Quelle application ouvre quoi"),
      "applications : elle n'est plus une deuxième page d'applications par défaut");
  dit(h.includes("allerA('confidentialite')") && h.includes("pas de bac à sable"),
      "applications : les permissions d'Ubuntu sont expliquées, pas imitées");
} catch (e) {
  console.log("NON|le rendu s'est arrêté : " + (e && e.message || e));
}
console.log("FIN|");
JS
	SORTIE_P="$(node "$BANC/rendu.js" "$PAGE" 2>&1 | grep -E '^(OK|NON|FIN)\|' || true)"
	if [ -z "$SORTIE_P" ]; then
		non "les pages n'ont rien rendu"
	elif ! grep -q '^FIN|' <<< "$SORTIE_P"; then
		non "le rendu s'est arrêté avant la fin — des contrôles n'ont jamais tourné"
		while IFS='|' read -r V M; do
			[ "$V" = "NON" ] && non "$M"
		done <<EOF
$SORTIE_P
EOF
	else
		while IFS='|' read -r V M; do
			case "$V" in OK) ok "$M" ;; NON) non "$M" ;; esac
		done <<EOF
$SORTIE_P
EOF
	fi
fi

# =============================================================================
titre "4. UNE SEULE SOURCE, ET DES ACTIONS QUI EXISTENT"
# =============================================================================
sed 's|#.*$||' "$MOTEUR" > "$BANC/moteur.py"
for COUPLE in "terminal-mode:act_terminal:lexos-terminal" \
              "bienetre:act_bienetre:lexos-bienetre" \
              "comptes:act_comptes:lexos-comptes" \
              "recherche:act_recherche:lexos-recherche"; do
	CLE="${COUPLE%%:*}"; RESTE="${COUPLE#*:}"; FN="${RESTE%%:*}"; OUTIL="${RESTE#*:}"
	grep -q "\"$CLE\": $FN" "$BANC/moteur.py" \
		&& ok "l'action « $CLE » est dans la table ACTIONS" \
		|| non "l'action « $CLE » n'est pas dans la table ACTIONS"
	grep -q "$OUTIL" "$BANC/moteur.py" \
		&& ok "le moteur passe par $OUTIL" \
		|| non "le moteur ne passe pas par $OUTIL"
	#  ACTIONS est évaluée À L'IMPORT : une fonction définie après la table
	#  donne un NameError au chargement, et les Paramètres ne s'ouvrent plus.
	LA="$(grep -n "^def $FN" "$MOTEUR" | head -1 | cut -d: -f1)"
	LT="$(grep -n '^ACTIONS = {' "$MOTEUR" | head -1 | cut -d: -f1)"
	if [ -n "$LA" ] && [ -n "$LT" ] && [ "$LA" -lt "$LT" ]; then
		ok "$FN est définie AVANT la table ACTIONS"
	else
		non "$FN est définie après ACTIONS : le module ne s'importerait pas"
	fi
done

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
