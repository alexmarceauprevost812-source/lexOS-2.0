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
#     « <<UNSUPPORTED>> » à la place de chaque tableau ;
#   · une FAUSSE barre qui, en partant (« -r » ou « --quit »),
#     réenregistre les lanceurs qu'elle avait chargés — comme xfce4-panel
#     4.20 (panel-application.c, SAVE_PLUGIN_PROVIDERS). Un nettoyage qui
#     ne repasserait pas derrière elle laisserait plugin-9 revivre.
#
#  Et la garde de la boîte « No running instance… » : « xfce4-panel -r »
#  sans barre qui réponde sur D-Bus propose de la RALLUMER (main.c). Le
#  banc exige qu'on ne l'appelle pas dans ce cas.
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
    print(f"Value is an array with {len(v)} items:\n")
    for x in v: print(montrer(x))
else:
    print(montrer(v))
PY

# --- La fausse barre ---------------------------------------------------------
#  $FAUX_BARRE existe = la barre tourne (il contient son pid) ;
#  $FAUX_BARRE.charges = les lanceurs qu'elle a chargés à son démarrage.
cat > "$BANC/bin/xfce4-panel" <<'PY'
#!/usr/bin/env python3
import json, os, sys
B = os.environ["FAUX_BARRE"]; X = os.environ["FAUX_XFCONF"]
open(B + ".appels", "a").write(" ".join(sys.argv[1:]) + "\n")
def charger(d):
    ids = d.get("/panels/panel-1/plugin-ids", [])
    return {str(n): d.get(f"/plugins/plugin-{n}/items", []) for n in ids
            if d.get(f"/plugins/plugin-{n}") == "launcher"}
def partir():
    #  Comme xfce4-panel 4.20 en partant : chaque greffon chargé réenregistre.
    d = json.load(open(X)); ch = json.load(open(B + ".charges"))
    for n, items in ch.items():
        d[f"/plugins/plugin-{n}"] = "launcher"; d[f"/plugins/plugin-{n}/items"] = items
    json.dump(d, open(X, "w"))
if not os.path.exists(B):
    sys.exit(1)
if sys.argv[1:2] == ["-r"]:
    partir()
    pid = int(open(B).read()) + 1
    open(B, "w").write(str(pid))
    json.dump(charger(json.load(open(X))), open(B + ".charges", "w"))
elif sys.argv[1:2] == ["--quit"]:
    partir(); os.remove(B)
PY
cat > "$BANC/bin/pgrep" <<'SH'
#!/bin/sh
[ -e "$FAUX_BARRE" ] || exit 1
cat "$FAUX_BARRE"; echo
SH
cat > "$BANC/bin/gdbus" <<'SH'
#!/bin/sh
if [ -e "$FAUX_BARRE" ] && [ -z "${FAUX_DBUS_MUET:-}" ]; then echo "(true,)"; else echo "(false,)"; fi
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

#  lancer <dossier> <arguments…> — dans un environnement de session factice.
lancer() {
	local H="$1"; shift
	env HOME="$H" XDG_CONFIG_HOME="$H/.config" XDG_STATE_HOME="$H/.local/state" \
		PATH="$BANC/bin:$PATH" FAUX_XFCONF="$H/xfconf.json" FAUX_BARRE="$H/barre" \
		bash "$SCRIPT" "$@"
}
barre_allumee() { echo 4242 > "$1/barre"; python3 - "$1" <<'PY'
import json, sys
H = sys.argv[1]; d = json.load(open(H + "/xfconf.json"))
ch = {str(n): d.get(f"/plugins/plugin-{n}/items", []) for n in d["/panels/panel-1/plugin-ids"]
      if d.get(f"/plugins/plugin-{n}") == "launcher"}
json.dump(ch, open(H + "/barre.charges", "w"))
PY
}
lire_ids() { python3 -c 'import json,sys; v=json.load(open(sys.argv[1]))["/panels/panel-1/plugin-ids"]; print(" ".join(map(str,v)) if isinstance(v,list) else "PAS-UN-TABLEAU:"+str(v))' "$1/xfconf.json"; }
cles() { python3 -c 'import json,sys; print("\n".join(sorted(json.load(open(sys.argv[1])))))' "$1/xfconf.json"; }
attendu="$(python3 -c 'import sys,xml.etree.ElementTree as E; r=E.parse(sys.argv[1]).getroot(); print(" ".join(v.get("value") for v in r.find("property[@name='"'"'panels'"'"']/property[@name='"'"'panel-1'"'"']/property[@name='"'"'plugin-ids'"'"']")))' "$SKEL_XML")"

echo "== Le banc peut rougir : le faux xfconf-query punit les mêmes fautes que le vrai"
H="$BANC/temoin"; compte "$H"
LV="$(env FAUX_XFCONF="$H/xfconf.json" "$BANC/bin/xfconf-query" -c xfce4-panel -lv)"
grep -E '^/panels/panel-1/plugin-ids +<<UNSUPPORTED>>$' <<<"$LV" >/dev/null \
	&& ok "« -lv » écrit <<UNSUPPORTED>> pour un tableau, comme le vrai" \
	|| non "« -lv » du faux montre les tableaux : la sauvegarde paraîtrait complète à tort"
env FAUX_XFCONF="$H/xfconf.json" "$BANC/bin/xfconf-query" -c xfce4-panel -p /panels/panel-1/plugin-ids -t int -s 1
[[ "$(lire_ids "$H")" == PAS-UN-TABLEAU:* ]] \
	&& ok "un « -s » seul sans « -a » change plugin-ids en nombre — la panne mesurée sur xfconfd est reproduite" \
	|| non "le faux xfconf-query ne reproduit pas la panne « -s sans -a » : le banc ne la verrait pas"

echo "== Mode classique, barre affichée : « lexos barre-haut nettoyer »"
H="$BANC/classique"; compte "$H"; barre_allumee "$H"
cles "$H" > "$BANC/avant.cles"
SORTIE="$(lancer "$H" nettoyer 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "nettoyer rend 0" || non "nettoyer rend $rc : $SORTIE"
[ "$(lire_ids "$H")" = "$attendu" ] \
	&& ok "plugin-ids = $attendu — exactement la barre du squelette, ordre gardé, bouton power dernier" \
	|| non "plugin-ids = « $(lire_ids "$H") », attendu « $attendu »"
RESTE="$(cles "$H" | grep -E '^/plugins/plugin-(9|10|11|21)(/|$)' || true)"
[ -z "$RESTE" ] \
	&& ok "plus rien sous plugin-9/10/11/21 — même après que la barre, en partant, les a réenregistrés" \
	|| non "il reste : $(tr '\n' ' ' <<<"$RESTE")"
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
        if c.get("type") not in ("array", "empty") and str(d.get(k + "/" + c.get("name"))).lower() != str(c.get("value")).lower():
            sys.exit(1)
PY
P="$H/.config/xfce4/panel"; S="$H/.local/state/lexos/barre-sans-captures"
[ ! -e "$P/launcher-9" ] && [ ! -e "$P/launcher-10" ] && [ ! -e "$P/launcher-11" ] && [ ! -e "$P/launcher-21" ] \
	&& ok "les dossiers launcher-9, -10, -11 et -21 ont quitté ~/.config/xfce4/panel" \
	|| non "un dossier de lanceur de capture est resté : $(ls "$P" | tr '\n' ' ')"
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
[ -e "$S/fait" ] && ok "le fanion « fait » est posé" || non "pas de fanion"
grep -q 'greffons 9 10 11 21' <<<"$SORTIE" && ok "le message dit lesquels : « $(grep -o 'greffons[^)]*' <<<"$SORTIE") »" || non "message : $SORTIE"

echo "== Deuxième passage, puis ouverture de session : rien ne bouge"
: > "$H/xfconf.json.log"
SORTIE="$(lancer "$H" nettoyer 2>&1)"
grep -q 'rien à retirer' <<<"$SORTIE" && ok "« nettoyer » refait : « rien à retirer »" || non "deuxième passage : $SORTIE"
grep -qE '(^| )-(s|r)( |$)' "$H/xfconf.json.log" && non "le deuxième passage a écrit dans xfconf" || ok "…sans une seule écriture"
[ "$(grep -c '^-r$' "$H/barre.appels")" = "1" ] && ok "…et sans relancer la barre" || non "la barre a été relancée pour rien"
: > "$H/xfconf.json.log"
lancer "$H" demarrer >/dev/null 2>&1
[ ! -s "$H/xfconf.json.log" ] && ok "« demarrer » avec le fanion : xfconf n'est même pas interrogé" \
	|| non "« demarrer » refait le travail à chaque session"

echo "== Mode Moteur, barre éteinte exprès : « demarrer » à l'ouverture de session"
H="$BANC/moteur"; compte "$H"; barre_allumee "$H"
mkdir -p "$H/.config/lexos"; echo '{"mode": "moteur"}' > "$H/.config/lexos/bureau.json"
lancer "$H" demarrer >/dev/null 2>&1
[ "$(lire_ids "$H")" = "$attendu" ] && ok "plugin-ids nettoyé" || non "plugin-ids = « $(lire_ids "$H") »"
grep -qx -- '--quit' "$H/barre.appels" && ok "la barre XFCE est fermée (--quit), comme avant" || non "la barre n'a pas été fermée"
grep -qx -- '-r' "$H/barre.appels" && non "« -r » appelé alors que la barre doit rester fermée : elle reviendrait" \
	|| ok "pas de « -r » : la barre fermée exprès reste fermée"
RESTE="$(cles "$H" | grep -E '^/plugins/plugin-(9|10|11|21)(/|$)' || true)"
[ -z "$RESTE" ] && ok "et ce que la barre a réenregistré en partant est nettoyé derrière elle" || non "il reste : $(tr '\n' ' ' <<<"$RESTE")"

echo "== Mode Moteur, barre rallumée par Alex (« lexos barre-haut on »)"
H="$BANC/moteur-on"; compte "$H"; barre_allumee "$H"
mkdir -p "$H/.config/lexos"; echo '{"mode": "moteur"}' > "$H/.config/lexos/bureau.json"; echo on > "$H/.config/lexos/barre-haut"
lancer "$H" demarrer >/dev/null 2>&1
grep -qx -- '--quit' "$H/barre.appels" && non "la barre voulue a été fermée" || ok "la barre voulue n'est pas fermée"
grep -qx -- '-r' "$H/barre.appels" && ok "elle est relancée sans les boutons de capture" || non "pas relancée : les boutons resteraient à l'écran"

echo "== Barre qui ne répond pas sur D-Bus : jamais de « -r » à l'aveugle"
H="$BANC/muet"; compte "$H"; barre_allumee "$H"
env FAUX_DBUS_MUET=1 HOME="$H" XDG_CONFIG_HOME="$H/.config" XDG_STATE_HOME="$H/.local/state" \
	PATH="$BANC/bin:$PATH" FAUX_XFCONF="$H/xfconf.json" FAUX_BARRE="$H/barre" bash "$SCRIPT" nettoyer >/dev/null 2>&1
grep -qx -- '-r' "$H/barre.appels" 2>/dev/null \
	&& non "« -r » sans barre qui réponde : la boîte « No running instance… » proposerait de la rallumer" \
	|| ok "pas de « -r » : la boîte qui rallume la barre ne s'ouvre pas"
[ "$(lire_ids "$H")" = "$attendu" ] && ok "les réglages sont quand même nettoyés (pris au prochain démarrage)" || non "plugin-ids = « $(lire_ids "$H") »"

echo "== Lanceur mêlé : seule la capture part"
H="$BANC/mixte"; compte "$H" mixte
lancer "$H" nettoyer >/dev/null 2>&1
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d["/plugins/plugin-12/items"]==["lexos-volet-rapides.desktop"] and 12 in d["/panels/panel-1/plugin-ids"] else 1)' "$H/xfconf.json" \
	&& ok "le volet ▲ garde son élément et sa place, sans la capture de zone ajoutée" \
	|| non "le lanceur 12 a été abîmé ou retiré"

echo "== xfconfd injoignable (ssh, sudo, pas de session)"
H="$BANC/mort"; compte "$H"
SORTIE="$(env FAUX_XFCONF_MORT=1 HOME="$H" XDG_CONFIG_HOME="$H/.config" XDG_STATE_HOME="$H/.local/state" \
	PATH="$BANC/bin:$PATH" FAUX_XFCONF="$H/xfconf.json" FAUX_BARRE="$H/barre" bash "$SCRIPT" nettoyer 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && grep -q 'dans ta session, sans sudo' <<<"$SORTIE" \
	&& ok "échec dit tout haut : « $SORTIE »" || non "rc=$rc, sortie : $SORTIE"
[ ! -e "$H/.local/state/lexos/barre-sans-captures/fait" ] && ok "pas de fanion : la prochaine session réessaiera" || non "fanion posé sans rien avoir fait"
[ -d "$H/.config/xfce4/panel/launcher-9" ] && ok "et rien n'a été déplacé" || non "launcher-9 déplacé sans nettoyage xfconf"

echo "== Lancé avec sudo par erreur"
H="$BANC/root"; compte "$H"; barre_allumee "$H"
SORTIE="$(env FAUX_UID=0 HOME="$H" XDG_CONFIG_HOME="$H/.config" XDG_STATE_HOME="$H/.local/state" \
	PATH="$BANC/bin:$PATH" FAUX_XFCONF="$H/xfconf.json" FAUX_BARRE="$H/barre" bash "$SCRIPT" nettoyer 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && grep -q 'SANS sudo' <<<"$SORTIE" && [ ! -e "$H/xfconf.json.log" ] \
	&& ok "en root : refus dit tout haut, et xfconf n'est même pas interrogé" \
	|| non "en root : rc=$rc, sortie « $SORTIE »"

echo "== Branchements"
grep -qE '^Exec=(/usr/bin/)?lexos-barre-haut demarrer$' "$AUTOSTART" \
	&& ok "l'autostart appelle toujours « lexos-barre-haut demarrer »" || non "l'autostart n'appelle plus demarrer"
grep -qE '^	barre-haut\)[[:space:]]+exec lexos-barre-haut "\$@" ;;' "$RACINE/config/includes.chroot/usr/bin/lexos" \
	&& ok "« lexos barre-haut nettoyer » passe par le dispatcheur" || non "pas de branche barre-haut dans lexos"

# =============================================================================
printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"
[ "$echoues" -eq 0 ] || exit 1
printf '  \033[32mLes boutons de capture quittent la barre, chez Alex aussi — et rien d'"'"'autre ne bouge.\033[0m\n'
