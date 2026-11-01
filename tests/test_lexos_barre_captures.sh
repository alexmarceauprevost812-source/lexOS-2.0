#!/usr/bin/env bash
# =============================================================================
#  Les anciens boutons de capture quittent AUSSI un compte déjà créé
# =============================================================================
#  ALEX (2026-10-23) : « retirer définitivement les anciens outils de la
#  barre du haut : l'icône appareil photo, l'icône capture de zone, le
#  bouton rond orange d'enregistrement […] Applique aussi le changement sur
#  ma session actuelle. Ne touche à rien d'autre dans la barre. »
#
#  /etc/skel ne sert qu'aux comptes NEUFS. Chez Alex, la barre vit dans
#  xfconfd, et c'est lexos-barre-haut qui retire les greffons de capture —
#  une fois à l'ouverture de session (« demarrer »), ou tout de suite
#  (« nettoyer »). Ce banc le fait tourner pour de vrai contre :
#
#   · un FAUX xfconf-query qui reproduit ce qui a été MESURÉ sur xfconfd
#     4.18.1 : sans « -a », un seul « -s » change le tableau plugin-ids en
#     NOMBRE (la barre se vide) ; plusieurs « -s » sans autant de « -t »
#     échouent ; « -r » sans « -R » laisse les enfants ; « -lv » écrit
#     « <<UNSUPPORTED>> » à la place de chaque tableau ; et SURTOUT, sous
#     une langue française, l'en-tête des tableaux est TRADUIT (« La valeur
#     est un tableau de N éléments : »). La première version du nettoyage
#     l'a pris pour un élément et l'a écrit à la place des boutons : tous
#     les essais tournent donc en fr_CA, la langue de LexOS ;
#   · une FAUSSE barre qui, comme xfce4-panel 4.20, ne relit ses réglages
#     qu'au démarrage, n'écrit rien en partant, mais réécrit plugin-ids et
#     /plugins/plugin-N DEPUIS SA MÉMOIRE quand on lui retire un greffon
#     d'un clic droit (panel-application.c, SAVE_PLUGIN_IDS) ;
#   · un faux D-Bus : « -r » ou « --quit » sans barre qui tienne son nom
#     org.xfce.Panel ouvre une boîte de dialogue (main.c, dbus_return). Le
#     banc exige qu'on ne les lance jamais à l'aveugle.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$RACINE/config/includes.chroot/usr/bin/lexos-barre-haut"
AUTOSTART="$RACINE/config/includes.chroot/etc/xdg/autostart/lexos-barre-haut.desktop"
SKEL_XML="$RACINE/config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
SKEL_PANNEAU="$RACINE/config/includes.chroot/etc/skel/.config/xfce4/panel"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

reussis=0; echoues=0
ok()  { printf '  \033[32m✅\033[0m %s\n' "$1"; reussis=$((reussis+1)); }
non() { printf '  \033[31m❌\033[0m %s\n' "$1"; echoues=$((echoues+1)); }

# --- Le faux xfconf-query ----------------------------------------------------
mkdir -p "$BANC/bin"
cat > "$BANC/bin/xfconf-query" <<'PY'
#!/usr/bin/env python3
import json, os, sys
ETAT = os.environ["FAUX_XFCONF"]
with open(ETAT + ".log", "a", encoding="utf-8") as j:
    j.write(" ".join(sys.argv[1:]) + "\n")
if os.environ.get("FAUX_XFCONF_MORT"):
    print("Failed to init libxfconf: Cannot autolaunch D-Bus without X11 $DISPLAY.", file=sys.stderr)
    sys.exit(1)

#  La langue des messages, comme gettext la choisit : LC_ALL, sinon
#  LC_MESSAGES, sinon LANG ; « C » ou « POSIX » (C.UTF-8 compris) → pas de
#  traduction, et LANGUAGE est alors ignoré ; sinon LANGUAGE passe devant.
def langue():
    loc = os.environ.get("LC_ALL") or os.environ.get("LC_MESSAGES") or os.environ.get("LANG") or "C"
    if loc.split(".")[0] in ("C", "POSIX"):
        return "en"
    premiere = (os.environ.get("LANGUAGE") or "").split(":")[0]
    return (premiere or loc)[:2]
ENTETE = {"fr": "La valeur est un tableau de {} éléments :"}.get(langue(), "Value is an array with {} items:")

d = json.load(open(ETAT, encoding="utf-8"))
a = sys.argv[1:]
prop = None; types = []; vals = []; lister = verbeux = tableau = retirer = recursif = False
i = 0
while i < len(a):
    o = a[i]
    if o == "-c": i += 1
    elif o == "-p": i += 1; prop = a[i]
    elif o == "-t": i += 1; types.append(a[i])
    elif o == "-s": i += 1; vals.append(a[i])
    elif o == "-l": lister = True
    elif o == "-v": verbeux = True
    elif o == "-lv": lister = verbeux = True
    elif o == "-a": tableau = True
    elif o == "-r": retirer = True
    elif o == "-R": recursif = True
    i += 1
def typer(t, v):
    return int(v) if t in ("int", "uint") else v
def montrer(v):
    return "true" if v is True else "false" if v is False else str(v)
def ecrire():
    json.dump(d, open(ETAT, "w", encoding="utf-8"))
if lister:
    for k in sorted(d):
        v = d[k]
        if verbeux:
            print(f"{k:<40} {'<<UNSUPPORTED>>' if isinstance(v, list) else montrer(v)}")
        else:
            print(k)
    sys.exit(0)
#  MESURÉ sur 4.18.1 : une propriété verrouillée ne change pas, et
#  xfconf-query rend 0 SANS RIEN DIRE — en écriture comme en « -r ».
VERROU = os.environ.get("FAUX_XFCONF_VERROU")
if VERROU and (retirer or vals) and prop and prop.startswith(VERROU):
    sys.exit(0)
if retirer:
    if recursif:
        for k in [k for k in d if k == prop or k.startswith(prop + "/")]:
            del d[k]
    elif prop in d:
        del d[prop]
    else:
        print(f'Property "{prop}" does not exist on channel "xfce4-panel".', file=sys.stderr); sys.exit(1)
    ecrire(); sys.exit(0)
if vals:
    if tableau or len(vals) > 1:
        if len(types) != len(vals):
            print(f"There are {len(vals)} new values, but only {len(types)} types could be determined.", file=sys.stderr)
            sys.exit(1)
        d[prop] = [typer(t, v) for t, v in zip(types, vals)]
    else:
        ancien = d.get(prop)
        if ancien is None and not types:
            print("When creating a new property, the value type must be specified.", file=sys.stderr); sys.exit(1)
        t = types[0] if types else ("int" if isinstance(ancien, int) or (isinstance(ancien, list) and ancien and isinstance(ancien[0], int)) else "string")
        #  MESURÉ : sans « -a », le tableau devient un nombre.
        d[prop] = typer(t, vals[0])
    ecrire(); sys.exit(0)
if prop not in d:
    print(f'Property "{prop}" does not exist on channel "xfce4-panel".', file=sys.stderr); sys.exit(1)
v = d[prop]
if isinstance(v, list):
    print(ENTETE.format(len(v)) + "\n")
    for x in v: print(montrer(x))
else:
    print(montrer(v))
PY

# --- La fausse barre ---------------------------------------------------------
#  $FAUX_BARRE existe = la barre tourne (il contient son pid).
#  $FAUX_BARRE.memoire = ce qu'elle a chargé à son démarrage (plugin-ids et
#  le genre de chaque greffon) : c'est CELA qu'elle réécrit si on lui retire
#  un greffon d'un clic droit, pas ce que dit xfconf à ce moment-là.
cat > "$BANC/bin/xfce4-panel" <<'PY'
#!/usr/bin/env python3
import json, os, sys
B = os.environ["FAUX_BARRE"]; X = os.environ["FAUX_XFCONF"]
open(B + ".appels", "a").write(" ".join(sys.argv[1:]) + "\n")
def charger():
    d = json.load(open(X))
    ids = d.get("/panels/panel-1/plugin-ids", [])
    json.dump({"ids": ids, "genres": {str(n): d.get(f"/plugins/plugin-{n}") for n in ids}}, open(B + ".memoire", "w"))
if not os.path.exists(B):
    sys.exit(1)
if sys.argv[1:2] == ["-r"]:
    pid = int(open(B).read().strip()) + 1
    open(B, "w").write(str(pid)); charger()
elif sys.argv[1:2] == ["--quit"]:
    os.remove(B)
elif sys.argv[1:2] == ["--demarrer"]:      # pas une vraie option : le banc
    charger()
elif sys.argv[1:2] == ["--clic-retirer"]:  # pas une vraie option : le banc
    m = json.load(open(B + ".memoire")); d = json.load(open(X)); n = int(sys.argv[2])
    m["ids"] = [i for i in m["ids"] if i != n]
    d["/panels/panel-1/plugin-ids"] = m["ids"]
    for i in m["ids"]:
        d[f"/plugins/plugin-{i}"] = m["genres"][str(i)]
    for k in [k for k in d if k == f"/plugins/plugin-{n}" or k.startswith(f"/plugins/plugin-{n}/")]:
        del d[k]
    json.dump(d, open(X, "w")); json.dump(m, open(B + ".memoire", "w"))
PY
cat > "$BANC/bin/pgrep" <<'SH'
#!/bin/sh
[ -e "$FAUX_BARRE" ] || exit 1
cat "$FAUX_BARRE"; echo
SH
#  Le nom D-Bus : absent sans barre, absent si FAUX_DBUS_MUET, et absent
#  pendant les FAUX_DBUS_APRES premières questions (barre tout juste lancée).
cat > "$BANC/bin/gdbus" <<'SH'
#!/bin/sh
n=$(($(cat "$FAUX_BARRE.questions" 2>/dev/null || echo 0) + 1)); echo "$n" > "$FAUX_BARRE.questions"
if [ -e "$FAUX_BARRE" ] && [ -z "${FAUX_DBUS_MUET:-}" ] && [ "$n" -gt "${FAUX_DBUS_APRES:-0}" ]; then
	echo "dbus:oui" >> "$FAUX_BARRE.appels"; echo "(true,)"
else
	echo "dbus:non" >> "$FAUX_BARRE.appels"; echo "(false,)"
fi
SH
#  Le banc tourne parfois en root (conteneur) : « id -u » rend l'uid d'un
#  compte ordinaire, sauf quand un essai demande FAUX_UID=0.
cat > "$BANC/bin/id" <<'SH'
#!/bin/sh
if [ "${1:-}" = "-u" ]; then echo "${FAUX_UID:-1000}"; exit 0; fi
exec /usr/bin/id "$@"
SH
chmod +x "$BANC"/bin/*

# --- Un compte « d'avant » ---------------------------------------------------
#  Le squelette d'aujourd'hui, à qui on rend les anciens greffons 9, 10, 11
#  — plus un lanceur ajouté À LA MAIN (nom horodaté, numéro 21) qui fait une
#  capture de zone : on doit le reconnaître par son CONTENU.
compte() { # compte <dossier> [mixte]
	local H="$1" mixte="${2:-}"
	mkdir -p "$H/.config/xfce4/panel" "$H/.config/xfce4/xfconf/xfce-perchannel-xml"
	cp -a "$SKEL_PANNEAU/." "$H/.config/xfce4/panel/"
	cp "$SKEL_XML" "$H/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
	for n in 9:photo:"lexos capture":lexos-camera 10:zone:"lexos capture zone":lexos-capture-zone \
	         11:video:'lexos-pro-terminal --hold -e "lexos capture video"':lexos-capture-video; do
		IFS=: read -r id q ex ic <<<"$n"
		mkdir -p "$H/.config/xfce4/panel/launcher-$id"
		printf '[Desktop Entry]\nType=Application\nName=Capture\nExec=%s\nIcon=%s\n' "$ex" "$ic" \
			> "$H/.config/xfce4/panel/launcher-$id/lexos-capture-$q.desktop"
	done
	mkdir -p "$H/.config/xfce4/panel/launcher-21"
	printf '[Desktop Entry]\nType=Application\nName=Zone\nExec=lexos capture zone\nIcon=x\n' \
		> "$H/.config/xfce4/panel/launcher-21/16981234567.desktop"
	python3 - "$SKEL_XML" "$H/xfconf.json" "$mixte" <<'PY'
import json, sys, xml.etree.ElementTree as ET
r = ET.parse(sys.argv[1]).getroot(); d = {}
def val(t, v):
    return int(v) if t in ("int", "uint") else (v == "true") if t == "bool" else v
def marcher(n, base):
    for p in n.findall("property"):
        k = base + "/" + p.get("name"); t = p.get("type")
        if t == "array":
            d[k] = [val(v.get("type"), v.get("value")) for v in p.findall("value")]
        elif t != "empty":
            d[k] = val(t, p.get("value"))
        marcher(p, k)
marcher(r, "")
ids = d["/panels/panel-1/plugin-ids"]; i = ids.index(14) + 1
d["/panels/panel-1/plugin-ids"] = ids[:i] + [9, 10, 11, 21] + ids[i:]
for n, f in ((9, "lexos-capture-photo.desktop"), (10, "lexos-capture-zone.desktop"),
             (11, "lexos-capture-video.desktop"), (21, "16981234567.desktop")):
    d[f"/plugins/plugin-{n}"] = "launcher"; d[f"/plugins/plugin-{n}/items"] = [f]
if sys.argv[3]:
    d["/plugins/plugin-12/items"] = d["/plugins/plugin-12/items"] + ["lexos-capture-zone.desktop"]
json.dump(d, open(sys.argv[2], "w"))
PY
}

#  lancer <dossier> <arguments…> — dans une session factice, EN FRANÇAIS
#  comme LexOS (LANG=fr_CA.UTF-8, et LANGUAGE en prime). EXTRA ajoute des
#  variables le temps d'un essai.
EXTRA=()
lancer() {
	local H="$1"; shift
	env -u LC_ALL -u LC_MESSAGES LANG=fr_CA.UTF-8 LANGUAGE=fr_CA:fr \
		HOME="$H" XDG_CONFIG_HOME="$H/.config" XDG_STATE_HOME="$H/.local/state" \
		PATH="$BANC/bin:$PATH" FAUX_XFCONF="$H/xfconf.json" FAUX_BARRE="$H/barre" \
		"${EXTRA[@]}" bash "$SCRIPT" "$@"
}
barre() { # barre <dossier> <option…> — parler à la fausse barre
	local H="$1"; shift
	FAUX_XFCONF="$H/xfconf.json" FAUX_BARRE="$H/barre" "$BANC/bin/xfce4-panel" "$@"
}
barre_allumee() { echo 4242 > "$1/barre"; barre "$1" --demarrer; }
lire_ids() { python3 -c 'import json,sys; v=json.load(open(sys.argv[1]))["/panels/panel-1/plugin-ids"]; print(" ".join(map(str,v)) if isinstance(v,list) else "PAS-UN-TABLEAU:"+str(v))' "$1/xfconf.json"; }
cles() { python3 -c 'import json,sys; print("\n".join(sorted(json.load(open(sys.argv[1])))))' "$1/xfconf.json"; }
restes() { cles "$1" | grep -E '^/plugins/plugin-(9|10|11|21)(/|$)' || true; }
ecritures() { grep -cE '(^| )-(s|r)( |$)' "$1/xfconf.json.log" 2>/dev/null || true; }
attendu="$(python3 -c 'import sys,xml.etree.ElementTree as E; r=E.parse(sys.argv[1]).getroot(); print(" ".join(v.get("value") for v in r.find("property[@name='"'"'panels'"'"']/property[@name='"'"'panel-1'"'"']/property[@name='"'"'plugin-ids'"'"']")))' "$SKEL_XML")"
S_REL=".local/state/lexos/barre-sans-captures"

echo "== Le banc peut rougir : le faux xfconf-query punit les mêmes fautes que le vrai"
H="$BANC/temoin"; compte "$H"
LV="$(env FAUX_XFCONF="$H/xfconf.json" "$BANC/bin/xfconf-query" -c xfce4-panel -lv)"
grep -E '^/panels/panel-1/plugin-ids +<<UNSUPPORTED>>$' <<<"$LV" >/dev/null \
	&& ok "« -lv » écrit <<UNSUPPORTED>> pour un tableau, comme le vrai" \
	|| non "« -lv » du faux montre les tableaux : la sauvegarde paraîtrait complète à tort"
FR="$(env -u LC_ALL LANG=fr_CA.UTF-8 FAUX_XFCONF="$H/xfconf.json" "$BANC/bin/xfconf-query" -c xfce4-panel -p /plugins/plugin-9/items | head -n 1)"
CU="$(env LC_ALL=C.UTF-8 LANGUAGE=fr FAUX_XFCONF="$H/xfconf.json" "$BANC/bin/xfconf-query" -c xfce4-panel -p /plugins/plugin-9/items | head -n 1)"
[ "$FR" = "La valeur est un tableau de 1 éléments :" ] && [ "$CU" = "Value is an array with 1 items:" ] \
	&& ok "en fr_CA l'en-tête est traduit, en C.UTF-8 il ne l'est pas (même avec LANGUAGE=fr) — comme le vrai" \
	|| non "le faux ne traduit pas comme le vrai : « $FR » / « $CU »"
env FAUX_XFCONF="$H/xfconf.json" "$BANC/bin/xfconf-query" -c xfce4-panel -p /panels/panel-1/plugin-ids -t int -s 1
[[ "$(lire_ids "$H")" == PAS-UN-TABLEAU:* ]] \
	&& ok "un « -s » seul sans « -a » change plugin-ids en nombre — la panne mesurée sur xfconfd est reproduite" \
	|| non "le faux xfconf-query ne reproduit pas la panne « -s sans -a » : le banc ne la verrait pas"

echo "== Mode classique, barre affichée : « lexos barre-haut nettoyer » (en fr_CA)"
H="$BANC/classique"; compte "$H"; barre_allumee "$H"
cles "$H" > "$BANC/avant.cles"
SORTIE="$(lancer "$H" nettoyer 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "nettoyer rend 0" || non "nettoyer rend $rc : $SORTIE"
[ "$(lire_ids "$H")" = "$attendu" ] \
	&& ok "plugin-ids = $attendu — exactement la barre du squelette, ordre gardé, bouton power dernier" \
	|| non "plugin-ids = « $(lire_ids "$H") », attendu « $attendu »"
[ -z "$(restes "$H")" ] && ok "plus rien sous plugin-9/10/11/21" || non "il reste : $(restes "$H" | tr '\n' ' ')"
grep -q 'tableau' "$H/xfconf.json" && non "l'en-tête traduit a été ÉCRIT dans les réglages de la barre" \
	|| ok "aucun « La valeur est un tableau… » écrit dans les réglages"
PERDU="$(comm -23 "$BANC/avant.cles" <(cles "$H") | grep -vE '^/plugins/plugin-(9|10|11|21)(/|$)' || true)"
[ -z "$PERDU" ] && ok "aucune autre propriété de la barre n'a disparu" || non "propriétés perdues : $(tr '\n' ' ' <<<"$PERDU")"
python3 - "$H/xfconf.json" "$SKEL_XML" <<'PY' && ok "les autres greffons (heure, météo, wifi/bluetooth, batterie, son, power) gardent leurs réglages" || non "un autre greffon a changé de réglages"
import json, sys, xml.etree.ElementTree as ET
d = json.load(open(sys.argv[1]))
r = ET.parse(sys.argv[2]).getroot()
for p in r.find("property[@name='plugins']").findall("property"):
    k = "/plugins/" + p.get("name")
    if d.get(k) != p.get("value"): sys.exit(1)
    for c in p.findall("property"):
        n = k + "/" + c.get("name")
        if c.get("type") == "array":
            if [v.get("value") for v in c.findall("value")] != [str(x) for x in d.get(n, [])]: sys.exit(1)
        elif c.get("type") != "empty" and str(d.get(n)).lower() != str(c.get("value")).lower():
            sys.exit(1)
PY
P="$H/.config/xfce4/panel"; S="$H/$S_REL"
[ ! -e "$P/launcher-9" ] && [ ! -e "$P/launcher-10" ] && [ ! -e "$P/launcher-11" ] && [ ! -e "$P/launcher-21" ] \
	&& ok "les dossiers launcher-9, -10, -11 et -21 ont quitté ~/.config/xfce4/panel" \
	|| non "un dossier de lanceur de capture est resté : $(find "$P" -mindepth 1 -maxdepth 1 -printf '%f ')"
ls -d "$S"/launcher-9.* "$S"/launcher-10.* "$S"/launcher-11.* "$S"/launcher-21.* >/dev/null 2>&1 \
	&& ok "…mis de côté dans la sauvegarde, pas effacés" || non "les dossiers ne sont pas dans la sauvegarde"
[ -f "$P/launcher-12/lexos-volet-rapides.desktop" ] && [ -f "$P/launcher-17/lexos-session.desktop" ] \
	&& ok "le volet ▲ (son) et le bouton power gardent leurs lanceurs" || non "launcher-12 ou -17 a été touché"
grep -qF '/panels/panel-1/plugin-ids = 1|14|9|10|11|21|' "$S"/avant-*.txt 2>/dev/null \
	&& ok "la sauvegarde lisible contient l'ANCIEN plugin-ids, tableau compris" \
	|| non "la sauvegarde ne contient pas l'ancien plugin-ids"
ls "$S"/avant-*.xml >/dev/null 2>&1 && ok "le fichier XML de xfconfd est copié tel quel" || non "pas de copie du XML"
[ "$(grep -c '^-r$' "$H/barre.appels" 2>/dev/null)" = "1" ] \
	&& ok "la barre affichée est relancée UNE fois (xfce4-panel -r)" \
	|| non "relances : « $(tr '\n' ' ' < "$H/barre.appels" 2>/dev/null) »"
[ -e "$S/fait-2" ] && ok "le fanion « fait-2 » est posé" || non "pas de fanion"
[ "$(sort -n "$S/retires" 2>/dev/null | paste -sd ' ')" = "9 10 11 21" ] \
	&& ok "les numéros retirés sont notés (9 10 11 21)" || non "numéros notés : « $(paste -sd ' ' "$S/retires" 2>/dev/null) »"
grep -q 'greffons 9 10 11 21' <<<"$SORTIE" && ok "le message dit lesquels : « $(grep -o 'greffons[^)]*' <<<"$SORTIE") »" || non "message : $SORTIE"

echo "== Deuxième passage, puis ouverture de session : rien ne bouge"
: > "$H/xfconf.json.log"
SORTIE="$(lancer "$H" nettoyer 2>&1)"
grep -q 'rien à retirer' <<<"$SORTIE" && ok "« nettoyer » refait : « rien à retirer »" || non "deuxième passage : $SORTIE"
[ "$(ecritures "$H")" = "0" ] && ok "…sans une seule écriture" || non "le deuxième passage a écrit dans xfconf"
[ "$(grep -c '^-r$' "$H/barre.appels")" = "1" ] && ok "…et sans relancer la barre" || non "la barre a été relancée pour rien"
: > "$H/xfconf.json.log"
#  Première session après la mise à jour : la barre passe en « cachée »
#  (autohide-behavior=2) UNE fois, demande d'Alex du 2026-11-01.
lancer "$H" demarrer >/dev/null 2>&1
grep -q -- '/panels/panel-1/autohide-behavior .*-s 2' "$H/xfconf.json.log" \
	&& ok "« demarrer » cache la barre une première fois (autohide-behavior=2)" \
	|| non "la barre n'a pas été passée en cachée : $(tr '\n' ';' < "$H/xfconf.json.log")"
[ -e "$H/.local/state/lexos/barre-auto-1" ] && ok "…et pose le fanion barre-auto-1" || non "pas de fanion barre-auto-1"
: > "$H/xfconf.json.log"
lancer "$H" demarrer >/dev/null 2>&1
[ "$(ecritures "$H")" = "0" ] && ! grep -q -- ' -l$' "$H/xfconf.json.log" \
	&& ok "« demarrer » avec le fanion : ni écriture, ni relecture de toute la barre (juste les numéros retirés)" \
	|| non "« demarrer » refait le travail à chaque session : $(tr '\n' ';' < "$H/xfconf.json.log")"

echo "== Mode Moteur, barre éteinte exprès : « demarrer » à l'ouverture de session"
H="$BANC/moteur"; compte "$H"; barre_allumee "$H"
mkdir -p "$H/.config/lexos"; echo '{"mode": "moteur"}' > "$H/.config/lexos/bureau.json"
lancer "$H" demarrer >/dev/null 2>&1
[ "$(lire_ids "$H")" = "$attendu" ] && ok "plugin-ids nettoyé" || non "plugin-ids = « $(lire_ids "$H") »"
grep -qx -- '--quit' "$H/barre.appels" && ok "la barre XFCE est fermée (--quit), comme avant" || non "la barre n'a pas été fermée"
grep -qx -- '-r' "$H/barre.appels" && non "« -r » appelé alors que la barre doit rester fermée : elle reviendrait" \
	|| ok "pas de « -r » : la barre fermée exprès reste fermée"
[ -z "$(restes "$H")" ] && ok "plus rien sous plugin-9/10/11/21" || non "il reste : $(restes "$H" | tr '\n' ' ')"

echo "== Mode Moteur, barre tout juste lancée, pas encore sur D-Bus"
H="$BANC/tardive"; compte "$H"; barre_allumee "$H"
mkdir -p "$H/.config/lexos"; echo '{"mode": "moteur"}' > "$H/.config/lexos/bureau.json"
EXTRA=(FAUX_DBUS_APRES=2); lancer "$H" demarrer >/dev/null 2>&1; EXTRA=()
python3 - "$H/barre.appels" <<'PY' && ok "« --quit » attend que la barre réponde : aucune boîte « Failed to quit the panel »" || non "« --quit » lancé à l'aveugle : $(tr '\n' ' ' < "$H/barre.appels")"
import sys
l = [x.strip() for x in open(sys.argv[1])]
q = [i for i, x in enumerate(l) if x == "--quit"]
sys.exit(0 if q and all(i > 0 and l[i - 1] == "dbus:oui" for i in q) and "dbus:non" in l else 1)
PY

echo "== Mode Moteur, barre rallumée par Alex (« lexos barre-haut on »)"
H="$BANC/moteur-on"; compte "$H"; barre_allumee "$H"
mkdir -p "$H/.config/lexos"; echo '{"mode": "moteur"}' > "$H/.config/lexos/bureau.json"; echo on > "$H/.config/lexos/barre-haut"
lancer "$H" demarrer >/dev/null 2>&1
grep -qx -- '--quit' "$H/barre.appels" && non "la barre voulue a été fermée" || ok "la barre voulue n'est pas fermée"
grep -qx -- '-r' "$H/barre.appels" && ok "elle est relancée sans les boutons de capture" || non "pas relancée : les boutons resteraient à l'écran"

echo "== Barre qui ne répond pas sur D-Bus, puis clic droit → Retirer sur un bouton encore visible"
H="$BANC/muet"; compte "$H"; barre_allumee "$H"
EXTRA=(FAUX_DBUS_MUET=1); SORTIE="$(lancer "$H" nettoyer 2>&1)"; EXTRA=()
grep -qx -- '-r' "$H/barre.appels" 2>/dev/null \
	&& non "« -r » sans barre qui réponde : une boîte de dialogue s'ouvrirait" \
	|| ok "pas de « -r » : aucune boîte de dialogue"
[ "$(lire_ids "$H")" = "$attendu" ] && ok "les réglages sont quand même nettoyés" || non "plugin-ids = « $(lire_ids "$H") »"
[ ! -e "$H/$S_REL/fait-2" ] && grep -q 'prochaine ouverture de session' <<<"$SORTIE" \
	&& ok "pas de fanion : la barre affiche encore les boutons, la prochaine session repasse — et c'est dit" \
	|| non "fanion posé alors que la barre garde les boutons en mémoire (sortie : $SORTIE)"
barre "$H" --clic-retirer 9
[ "$(lire_ids "$H")" != "$attendu" ] && ok "(la barre restée en mémoire a réécrit 10, 11, 21 dans plugin-ids, sans items)" \
	|| non "le clic droit simulé n'a rien réécrit : l'essai suivant ne prouve rien"
barre "$H" -r >/dev/null; : > "$H/barre.appels"
lancer "$H" demarrer >/dev/null 2>&1
[ "$(lire_ids "$H")" = "$attendu" ] && [ -z "$(restes "$H")" ] \
	&& ok "à la session suivante, les lanceurs vides 10, 11, 21 repartent" \
	|| non "après la session suivante : plugin-ids = « $(lire_ids "$H") », restes : $(restes "$H" | tr '\n' ' ')"
[ -e "$H/$S_REL/fait-2" ] && ok "…et le fanion est posé" || non "fanion toujours absent"

echo "== Mode Moteur, barre ouverte à la main : fanion posé, puis un numéro retiré revient"
H="$BANC/revenant"; compte "$H"; barre_allumee "$H"
mkdir -p "$H/.config/lexos"; echo '{"mode": "moteur"}' > "$H/.config/lexos/bureau.json"
lancer "$H" nettoyer >/dev/null 2>&1
[ -e "$H/$S_REL/fait-2" ] && ! grep -qx -- '-r' "$H/barre.appels" \
	&& ok "barre non voulue : pas de relance, fanion posé" || non "relance ou fanion inattendus"
barre "$H" --clic-retirer 9
lancer "$H" demarrer >/dev/null 2>&1
[ "$(lire_ids "$H")" = "$attendu" ] && [ -z "$(restes "$H")" ] \
	&& ok "« demarrer » voit les numéros revenus malgré le fanion et les retire" \
	|| non "les lanceurs revenus restent : plugin-ids = « $(lire_ids "$H") »"

echo "== Un numéro libéré redonné par la barre à un NOUVEAU lanceur d'Alex"
H="$BANC/reprise"; compte "$H"
lancer "$H" nettoyer >/dev/null 2>&1
python3 - "$H/xfconf.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["/plugins/plugin-9"] = "launcher"; d["/plugins/plugin-9/items"] = ["firefox-esr.desktop"]
d["/panels/panel-1/plugin-ids"] = d["/panels/panel-1/plugin-ids"][:-1] + [9, 17]
json.dump(d, open(sys.argv[1], "w"))
PY
lancer "$H" demarrer >/dev/null 2>&1
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get("/plugins/plugin-9/items")==["firefox-esr.desktop"] and 9 in d["/panels/panel-1/plugin-ids"] else 1)' "$H/xfconf.json" \
	&& ok "le nouveau lanceur d'Alex au numéro 9 (Firefox) reste en place" || non "le nouveau lanceur 9 d'Alex a été retiré"
: > "$H/xfconf.json.log"; lancer "$H" demarrer >/dev/null 2>&1
! grep -qx '9' "$H/$S_REL/retires" && ! grep -q -- ' -l$' "$H/xfconf.json.log" \
	&& ok "…et le numéro 9 est oublié : plus de passage complet à chaque session" \
	|| non "le numéro 9 reste noté, ou chaque session refait tout le passage"

echo "== Compte déjà passé par la PREMIÈRE version (en-tête traduit écrit dans les lanceurs)"
H="$BANC/abime"; compte "$H"
python3 - "$H/xfconf.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for n in (9, 10, 11, 21):
    d[f"/plugins/plugin-{n}/items"] = ["La valeur est un tableau de 1 éléments :"]
d["/plugins/plugin-12/items"] = ["La valeur est un tableau de 1 éléments :", "lexos-volet-rapides.desktop"]
json.dump(d, open(sys.argv[1], "w"))
PY
#  La barre, recevant ces items, a effacé les .desktop de launcher-N
#  (launcher.c, launcher_plugin_items_delete_configs) ; et la première
#  version avait posé son fanion « fait ».
rm -f "$H/.config/xfce4/panel/launcher-"{9,10,11,21}/*.desktop
mkdir -p "$H/$S_REL"; touch "$H/$S_REL/fait"
lancer "$H" demarrer >/dev/null 2>&1
[ "$(lire_ids "$H")" = "$attendu" ] && [ -z "$(restes "$H")" ] \
	&& ok "les trois lanceurs abîmés (et le 21) partent malgré l'ancien fanion « fait »" \
	|| non "lanceurs abîmés restés : plugin-ids = « $(lire_ids "$H") »"
python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1]))["/plugins/plugin-12/items"]==["lexos-volet-rapides.desktop"] else 1)' "$H/xfconf.json" \
	&& ok "le volet ▲ perd le débris et garde son élément" || non "le volet ▲ garde le débris ou a perdu son élément"

echo "== Lanceur mêlé : seule la capture part"
H="$BANC/mixte"; compte "$H" mixte
lancer "$H" nettoyer >/dev/null 2>&1
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d["/plugins/plugin-12/items"]==["lexos-volet-rapides.desktop"] and 12 in d["/panels/panel-1/plugin-ids"] else 1)' "$H/xfconf.json" \
	&& ok "le volet ▲ garde son élément et sa place, sans la capture de zone ajoutée" \
	|| non "le lanceur 12 a été abîmé ou retiré"

echo "== Plusieurs barres : une à qui il reste UN greffon, une qui se vide"
H="$BANC/multi"; compte "$H"
python3 - "$H/xfconf.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["/panels"] = [1, 2, 3]
d["/panels/panel-2/plugin-ids"] = [10, 30]; d["/plugins/plugin-30"] = "separator"
d["/panels/panel-3/plugin-ids"] = [11]
json.dump(d, open(sys.argv[1], "w"))
PY
lancer "$H" nettoyer >/dev/null 2>&1
python3 - "$H/xfconf.json" "$attendu" <<'PY' && ok "panel-1 nettoyé, panel-2 garde [30] en TABLEAU (pas le nombre 30), panel-3 vidé proprement" || non "plusieurs barres mal traitées : $(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print({k:v for k,v in d.items() if k.startswith("/panels")})' "$H/xfconf.json")"
import json, sys
d = json.load(open(sys.argv[1]))
ok = (" ".join(map(str, d["/panels/panel-1/plugin-ids"])) == sys.argv[2]
      and d.get("/panels/panel-2/plugin-ids") == [30]
      and "/panels/panel-3/plugin-ids" not in d
      and d.get("/plugins/plugin-30") == "separator")
sys.exit(0 if ok else 1)
PY

echo "== xfconf refuse une écriture (propriété verrouillée)"
H="$BANC/verrou"; compte "$H"
EXTRA=(FAUX_XFCONF_VERROU=/panels/); SORTIE="$(lancer "$H" nettoyer 2>&1)"; rc=$?; EXTRA=()
[ "$rc" -ne 0 ] && grep -q 'la prochaine session réessaiera' <<<"$SORTIE" \
	&& ok "écriture refusée : échec dit tout haut, rc=$rc" || non "rc=$rc, sortie : $SORTIE"
[ ! -e "$H/$S_REL/fait-2" ] && ok "pas de fanion : la prochaine session réessaiera" || non "fanion posé malgré l'écriture refusée"
[ -d "$H/.config/xfce4/panel/launcher-9" ] && grep -qx '/plugins/plugin-9' < <(cles "$H") \
	&& ok "ni les greffons ni les dossiers n'ont été retirés à moitié" || non "retrait à moitié fait"

echo "== xfconfd injoignable (ssh, sudo, pas de session)"
H="$BANC/mort"; compte "$H"
EXTRA=(FAUX_XFCONF_MORT=1); SORTIE="$(lancer "$H" nettoyer 2>&1)"; rc=$?; EXTRA=()
[ "$rc" -ne 0 ] && grep -q 'dans ta session, sans sudo' <<<"$SORTIE" \
	&& ok "échec dit tout haut : « $SORTIE »" || non "rc=$rc, sortie : $SORTIE"
[ ! -e "$H/$S_REL/fait-2" ] && ok "pas de fanion : la prochaine session réessaiera" || non "fanion posé sans rien avoir fait"
[ -d "$H/.config/xfce4/panel/launcher-9" ] && ok "et rien n'a été déplacé" || non "launcher-9 déplacé sans nettoyage xfconf"

echo "== Lancé avec sudo par erreur"
H="$BANC/root"; compte "$H"; barre_allumee "$H"
EXTRA=(FAUX_UID=0); SORTIE="$(lancer "$H" nettoyer 2>&1)"; rc=$?; EXTRA=()
[ "$rc" -ne 0 ] && grep -q 'SANS sudo' <<<"$SORTIE" && [ ! -e "$H/xfconf.json.log" ] \
	&& ok "en root : refus dit tout haut, et xfconf n'est même pas interrogé" \
	|| non "en root : rc=$rc, sortie « $SORTIE »"

echo "== Branchements"
grep -qE '^Exec=(/usr/bin/)?lexos-barre-haut demarrer$' "$AUTOSTART" \
	&& ok "l'autostart appelle toujours « lexos-barre-haut demarrer »" || non "l'autostart n'appelle plus demarrer"
grep -qE '^	barre-haut\)[[:space:]]+exec lexos-barre-haut "\$@" ;;' "$RACINE/config/includes.chroot/usr/bin/lexos" \
	&& ok "« lexos barre-haut nettoyer » passe par le dispatcheur" || non "pas de branche barre-haut dans lexos"
DIRECTS="$(grep -nE '^[^#]*xfconf-query -c' "$SCRIPT" | grep -v 'xq() {' || true)"
grep -qE '^xq\(\) \{ LC_ALL=C\.UTF-8 xfconf-query ' "$SCRIPT" && [ -z "$DIRECTS" ] \
	&& ok "toute lecture de xfconf passe par xq(), en C.UTF-8" \
	|| non "un appel à xfconf-query contourne xq() : sa sortie serait traduite — $DIRECTS"

# =============================================================================
printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"
[ "$echoues" -eq 0 ] || exit 1
printf '  \033[32mLes boutons de capture quittent la barre, chez Alex aussi — et rien d'"'"'autre ne bouge.\033[0m\n'
