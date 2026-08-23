#!/usr/bin/env bash
# =============================================================================
#  verifier.sh — la vérification d'avant-vol de LexOS
#
#  Une construction d'ISO coûte 75 minutes ; ce script coûte dix secondes.
#  Il rejoue EN LOCAL tout ce que la CI vérifiera, plus les contrôles nés des
#  pannes passées — chacun porte le nom de la panne qui l'a fait naître.
#
#      ./verifier.sh             # tout vérifier
#      ./verifier.sh --strict    # code de sortie 1 à la première famille en échec
#
#  Les documents du projet parlaient de « verifier.sh » depuis des semaines
#  sans qu'il existe : ses contrôles vivaient éparpillés — dans ci.yml, dans
#  verifier-parametres.sh, et dans des commandes refaites à la main avant
#  chaque build. Les voilà sous un seul toit, celui qu'on attendait.
# =============================================================================
set -uo pipefail

STRICT=0
[ "${1:-}" = "--strict" ] && STRICT=1
[ -f lexos.conf ] || { echo "✗ à lancer à la racine du dépôt"; exit 2; }

ROUGE=$'\033[31m'; VERT=$'\033[32m'; GRAS=$'\033[1m'; RAZ=$'\033[0m'
[ -t 1 ] || { ROUGE=""; VERT=""; GRAS=""; RAZ=""; }
ERREURS=0
bloc()  { printf '\n%s%s%s\n' "$GRAS" "$1" "$RAZ"; }
verdict() {  # $1 = code retour, $2 = libellé
  if [ "$1" -eq 0 ]; then printf '  %s✓%s %s\n' "$VERT" "$RAZ" "$2"
  else printf '  %s✗%s %s\n' "$ROUGE" "$RAZ" "$2"; ERREURS=$((ERREURS+1))
       [ "$STRICT" = 1 ] && exit 1; fi
}

BIN="config/includes.chroot/usr/bin"

# --- 1. Syntaxe de tous les scripts ------------------------------------------
bloc "1. Syntaxe (bash, sh, Python, JavaScript)"
R=0
while IFS= read -r f; do
  case "$(head -1 "$f")" in
    *bash*) bash -n "$f" || { echo "    $f"; R=1; } ;;
    *sh*)   sh -n "$f"   || { echo "    $f"; R=1; } ;;
  esac
done < <(find "$BIN" config/hooks config/includes.chroot/usr/lib/lexos \
              -maxdepth 2 -type f 2>/dev/null; ls verifier*.sh build.sh)
verdict $R "scripts shell"
R=0
find config/includes.chroot -name '*.py' -print0 2>/dev/null \
  | xargs -0 python3 -m py_compile 2>/dev/null || R=1
verdict $R "Python (py_compile)"
R=0
if command -v node >/dev/null 2>&1; then
  while IFS= read -r f; do
    node --check "$f" >/dev/null 2>&1 || { echo "    $f"; R=1; }
  done < <(find config/includes.chroot/usr/share/lexos -name '*.js' 2>/dev/null)
  verdict $R "JavaScript (node --check)"
else
  echo "  · node absent — JavaScript non vérifié ici (la CI le fera)"
fi

# --- 2. shellcheck, si présent -----------------------------------------------
bloc "2. shellcheck (mêmes fichiers et même niveau que la CI)"
#  ═══ LA MÊME LISTE QUE LA CI, ET LE MÊME NIVEAU. POURQUOI ═══
#  Ce bloc a dit « aucune erreur » juste avant que la CI tombe sur SC2148
#  dans secure-boot.sh. Deux écarts, et chacun suffisait :
#
#    · LA LISTE. Il ne regardait que /usr/bin et les hooks. Le dossier
#      usr/share/lexos/shell/, que la CI analyse, n'était jamais vu ici —
#      donc jamais vu AVANT de pousser.
#    · LE FILTRE DE SHEBANG. « head -1 | grep sh$\|bash » sautait tout
#      fichier sans shebang. Or SC2148 est PRÉCISÉMENT l'avertissement des
#      fichiers sans shebang : le filtre écartait d'office la seule
#      catégorie de fichiers capable de déclencher l'erreur qu'on cherche.
#      Un contrôle qui ne peut structurellement pas échouer ne contrôle rien.
#
#  Et « -S error » là où la CI emploie « -S warning » : un avertissement
#  passait ici et cassait là-bas.
#
#  D'où une SEULE liste, écrite une fois, celle que la CI emploie. Si elle
#  change d'un côté, elle doit changer de l'autre — un contrôle local qui
#  ment est pire que pas de contrôle local, parce qu'on lui fait confiance.
SC_CIBLES="build.sh
auto/config
auto/build
auto/clean
tools/render-branding.sh
config/hooks/normal/*.hook.chroot
config/hooks/normal/*.hook.binary
config/includes.chroot/usr/bin/*
config/includes.chroot/etc/profile.d/lexos.sh
config/includes.chroot/usr/share/lexos/shell/*.sh"

if command -v shellcheck >/dev/null 2>&1; then
  R=0
  VUS=0
  for motif in $SC_CIBLES; do
    for f in $motif; do
      #  Le motif non développé (aucun fichier) : on passe. Sans ça, on
      #  analyserait une chaîne littérale et on croirait avoir tout vu.
      [ -f "$f" ] || continue
      VUS=$((VUS + 1))
      shellcheck -S warning "$f" >/dev/null 2>&1 || { echo "    $f"; R=1; }
    done
  done
  #  Zéro fichier analysé, c'est un succès en trompe-l'oeil : on le refuse.
  [ "$VUS" -gt 0 ] || { echo "    aucun fichier analysé — la liste est cassée"; R=1; }
  verdict $R "aucune erreur shellcheck ($VUS fichiers, même liste que la CI)"
else
  echo "  · shellcheck absent — sauté (la CI le fera)"
fi

# --- 3. XML du squelette ------------------------------------------------------
#  Né du fragment uca-fragment-prive.xml : un fichier invalide dans etc/skel
#  atterrit dans le dossier de CHAQUE utilisateur.
bloc "3. XML du squelette utilisateur"
R=0
while IFS= read -r f; do
  python3 -c "import xml.dom.minidom,sys;xml.dom.minidom.parse(sys.argv[1])" "$f" \
    2>/dev/null || { echo "    $f"; R=1; }
done < <(find config/includes.chroot/etc/skel -name '*.xml' 2>/dev/null)
verdict $R "tous les XML se parsent"

# --- 4. Balises genmon --------------------------------------------------------
#  Née du clic mort des tuiles : <click> n'existe pas, genmon jette en
#  silence ce qu'il ne connaît pas, et la tuile s'affiche sans rien faire.
bloc "4. Les tuiles du panneau n'emploient que des balises que genmon connaît"
CONNUES="txt txtclick img imgclick icon iconclick bar tool css"
R=0
for f in "$BIN"/*; do
  [ -f "$f" ] || continue
  grep -q -- '--panneau' "$f" || continue
  while IFS= read -r T; do
    ok=0; for C in $CONNUES; do [ "$T" = "$C" ] && ok=1 && break; done
    [ "$ok" = 0 ] && { echo "    $(basename "$f") : <$T>"; R=1; }
  done < <(grep -v '^[[:space:]]*#' "$f" \
           | grep -oE '<[a-z][a-z0-9]*>[^<]*</[a-z][a-z0-9]*>' \
           | sed 's/^<\([a-z0-9]*\)>.*/\1/' | sort -u)
done
verdict $R "balises connues seulement"

# --- 5. Backports épinglé -----------------------------------------------------
#  Née du piège llama.cpp : un paquet de trixie-backports sans l'archive
#  ouverte = construction verte, ISO sans la fonction, aucune erreur.
#
#  ⚠ Ce contrôle vérifie la PLOMBERIE, pas la PRÉMISSE. Il a été vert pendant
#    67 constructions alors que llama.cpp n'était dans aucune archive : les
#    deux fichiers config/archives/ existaient bien, ce qui manquait était le
#    paquet à l'autre bout. La vérification de la prémisse (le paquet est-il
#    réellement publié par backports ?) demande l'index de l'archive, donc du
#    réseau : elle vit dans la CI, pas ici. Un vert local ne prouve donc que
#    la moitié — c'est écrit pour que personne ne relise ça comme une preuve.
bloc "5. trixie-backports : ouvert quand il le faut, épinglé toujours"
R=0
if grep -qE '^[[:space:]]*llama\.cpp' \
     config/includes.chroot/usr/share/lexos/optional-packages/*.list 2>/dev/null; then
  grep -rqs 'trixie-backports' config/archives/*.list.chroot || R=1
  ls config/archives/*.pref.chroot >/dev/null 2>&1 || R=1
fi
verdict $R "archive ouverte + fichier d'épinglage présents"

# --- 6. Bits d'exécution ------------------------------------------------------
bloc "6. Bits d'exécution"
R=0
while IFS= read -r f; do
  [ -x "$f" ] || { echo "    $f"; R=1; }
done < <(find "$BIN" config/hooks/normal -maxdepth 1 -type f; ls build.sh auto/config auto/build 2>/dev/null)
verdict $R "tout est exécutable"

# --- 7. Numéros de hooks uniques ---------------------------------------------
#  Deux hooks au même numéro s'ordonnent par l'alphabet : déterministe,
#  mais ça tient à une lettre. Un numéro, un hook.
bloc "7. Chaque hook a son numéro à lui"
R=0
while IFS= read -r n; do
  echo "    numéro $n en double :"
  find config/hooks/normal -name "$n-*" -printf '      %f\n'
  R=1
done < <(find config/hooks/normal -type f -printf '%f\n' \
         | grep -oE '^[0-9]{4}' | sort | uniq -d)
verdict $R "aucun doublon de numéro"

# --- 8. Contrôle 16 -----------------------------------------------------------
bloc "8. Contrôle 16 — chaque outil est branché"
if [ -x ./verifier-parametres.sh ]; then
  ./verifier-parametres.sh --strict >/dev/null 2>&1
  verdict $? "verifier-parametres.sh --strict"
else
  verdict 1 "verifier-parametres.sh introuvable"
fi

# --- Bilan --------------------------------------------------------------------
bloc "Bilan"
if [ "$ERREURS" -eq 0 ]; then
  printf '  %s✓ prêt pour une construction%s\n' "$VERT" "$RAZ"
else
  printf '  %s✗ %s famille(s) de contrôles en échec — NE PAS construire%s\n' "$ROUGE" "$ERREURS" "$RAZ"
fi
[ "$ERREURS" -eq 0 ]
