#!/usr/bin/env bash
# =============================================================================
#  Le bandeau de l'installateur : lisible, et pas seulement bien orthographié
# =============================================================================
#  ALEX, PHOTO DE L'INSTALLATEUR : le bandeau de gauche était ILLISIBLE. Pas
#  « peu contrasté » — invisible : seule l'étape courante se distinguait, les
#  autres n'apparaissaient pas du tout.
#
#  ═══ LA CAUSE, ET POURQUOI ELLE ÉTAIT MUETTE ═══
#  Les quatre clés de « style: » étaient écrites en minuscule initiale
#  (« sidebarBackground »…). Calamares 3.3 les compare aux noms de son enum
#  C++ Branding::StyleEntry, résolus par QMetaEnum::valueToKey — donc avec une
#  MAJUSCULE initiale. Établi deux fois, sans deviner :
#    · les seules chaînes présentes dans le libcalamaresui.so 3.3.5 livré sont
#      SidebarBackground, SidebarBackgroundCurrent, SidebarText,
#      SidebarTextCurrent ; aucune variante en minuscule ;
#    · l'exemple officiel amont (src/branding/default/branding.desc) les écrit
#      avec la majuscule.
#
#  Une clé inconnue n'arrête RIEN : Calamares écrit « Unknown branding *style*
#  entry » dans un journal que personne ne lit, puis styleString() rend une
#  chaîne VIDE pour les quatre vraies entrées. QColor("") est invalide, et une
#  couleur invalide se peint en NOIR. D'où le noir sur noir, sans message.
#
#  ═══ CE QUE CE BANC GARDE ═══
#  L'orthographe exacte, oui — mais surtout le CONTRASTE. Écrire les bonnes
#  clés ne suffit pas : quelqu'un pourrait un jour poser un texte sombre sur un
#  fond sombre et refaire exactement la même panne, avec des clés valides
#  cette fois. On calcule donc le rapport de contraste des deux couples, comme
#  le ferait un œil.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$RACINE/config/hooks/normal/0500-lexos-installer.hook.chroot"

REUSSIS=0; ECHOUES=0
ok()    { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()   { printf '  \033[31m❌\033[0m %b\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre() { printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[[ -r "$HOOK" ]] || { echo "hook 0500 introuvable : $HOOK"; exit 1; }

#  On lit le bloc « style: » du heredoc de branding.desc, commentaires du
#  shell retirés : le commentaire au-dessus explique justement la casse et
#  cite les mauvaises clés, un grep naïf les compterait pour de vraies lignes.
BLOC="$(sed 's/^[[:space:]]*#.*$//' "$HOOK" \
	| sed -n '/^style:$/,/^EOF$/p' | sed '/^EOF$/d;/^style:$/d')"

# =============================================================================
titre "1. Les quatre clés existent, avec LEUR casse"
# =============================================================================
#  Les seules valides dans Calamares 3.3, telles que livrées dans le .so.
VALIDES=(SidebarBackground SidebarBackgroundCurrent SidebarText SidebarTextCurrent)

declare -A COULEUR=()
for K in "${VALIDES[@]}"; do
	V="$(printf '%s' "$BLOC" | sed -n "s/^[[:space:]]*${K}:[[:space:]]*\"\{0,1\}\([^\"]*\)\"\{0,1\}[[:space:]]*$/\1/p" | head -1)"
	if [[ -n "$V" ]]; then
		ok "$K est posée (« $V »)"
		COULEUR[$K]="$V"
	else
		non "$K MANQUE ou est mal orthographiée — Calamares la lira vide, donc NOIRE"
	fi
done

# =============================================================================
titre "2. Aucune clé que Calamares ne connaît pas"
# =============================================================================
#  ═══ LE CONTRÔLE QUI AURAIT ÉVITÉ LA PANNE ═══
#  Une clé inconnue ne fait rien échouer : elle est notée dans un journal et
#  la vraie entrée reste vide, donc noire. C'est exactement ce qui s'est
#  produit — et rien, nulle part, ne le signalait.
INCONNUES=""
while IFS= read -r LIGNE; do
	[[ -z "${LIGNE// }" ]] && continue
	CLE="$(printf '%s' "$LIGNE" | sed -n 's/^[[:space:]]*\([A-Za-z]*\):.*$/\1/p')"
	[[ -z "$CLE" ]] && continue
	CONNUE=0
	for K in "${VALIDES[@]}"; do [[ "$CLE" == "$K" ]] && CONNUE=1; done
	(( CONNUE == 0 )) && INCONNUES="$INCONNUES $CLE"
done <<< "$BLOC"

if [[ -z "${INCONNUES// }" ]]; then
	ok "aucune clé inconnue dans le bloc « style: »"
else
	non "clés que Calamares ignorera EN SILENCE :$INCONNUES\n     (les vraies entrées resteraient vides, donc peintes en noir)"
fi

#  Le piège nommé : « sidebarTextSelect » vient de Calamares 3.2 et n'existe
#  plus. On le cite pour que le rouge dise quoi faire, pas seulement qu'il y
#  a un problème.
if printf '%s' "$BLOC" | grep -qi 'sidebarTextSelect'; then
	non "« sidebarTextSelect » est une clé de Calamares 3.2, disparue en 3.3 — la bonne est SidebarBackgroundCurrent"
else
	ok "la clé morte « sidebarTextSelect » (Calamares 3.2) n'est plus là"
fi

# =============================================================================
titre "3. LE CONTRASTE — écrire les bonnes clés ne suffit pas"
# =============================================================================
#  Rapport de contraste WCAG entre deux couleurs. 4,5 est le seuil courant
#  pour du texte ; on exige 4,5 pour l'étape courante comme pour les autres.
#  Sans ce contrôle, un texte sombre sur fond sombre referait la panne avec
#  des clés parfaitement valides.
contraste() { # contraste <#rrggbb> <#rrggbb>
	python3 - "$1" "$2" <<'PY'
import sys
def lum(c):
    c = c.lstrip('#')
    if len(c) != 6: return None
    v = []
    for i in (0, 2, 4):
        x = int(c[i:i+2], 16) / 255
        v.append(x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4)
    return 0.2126*v[0] + 0.7152*v[1] + 0.0722*v[2]
a, b = lum(sys.argv[1]), lum(sys.argv[2])
if a is None or b is None:
    print("0"); raise SystemExit
hi, lo = max(a, b), min(a, b)
print("%.2f" % ((hi + 0.05) / (lo + 0.05)))
PY
}

verifie_paire() { # verifie_paire <cle_texte> <cle_fond> <libelle>
	local T="${COULEUR[$1]:-}" F="${COULEUR[$2]:-}"
	if [[ -z "$T" || -z "$F" ]]; then
		non "$3 : couleurs absentes, contraste incalculable"
		return
	fi
	local R; R="$(contraste "$T" "$F")"
	if awk -v r="$R" 'BEGIN{exit !(r >= 4.5)}'; then
		ok "$3 : contraste ${R}:1 — lisible"
	else
		non "$3 : contraste ${R}:1 seulement ($T sur $F) — c'est la panne d'origine qui revient"
	fi
}

verifie_paire SidebarText        SidebarBackground        "étapes non courantes"
verifie_paire SidebarTextCurrent SidebarBackgroundCurrent "étape courante"

#  ET LES DEUX FONDS DOIVENT SE DISTINGUER, sinon l'étape courante ne se
#  repère plus, même avec un texte lisible.
if [[ -n "${COULEUR[SidebarBackground]:-}" && -n "${COULEUR[SidebarBackgroundCurrent]:-}" ]]; then
	if [[ "${COULEUR[SidebarBackground]}" == "${COULEUR[SidebarBackgroundCurrent]}" ]]; then
		non "les deux fonds sont identiques : on ne verrait plus OÙ on en est"
	else
		ok "le fond de l'étape courante se distingue de celui des autres"
	fi
fi

# =============================================================================
titre "4. Le bloc part bien dans branding.desc"
# =============================================================================
#  Écrit ailleurs que dans le heredoc, il n'atteindrait aucun fichier.
if sed -n '/cat > "\$BRANDING_DIR\/branding.desc" <<EOF/,/^EOF$/p' "$HOOK" | grep -q '^style:$'; then
	ok "le bloc « style: » est bien DANS le heredoc de branding.desc"
else
	non "le bloc « style: » est hors du heredoc : il n'atteindrait pas branding.desc"
fi

#  Et le hook doit rester du shell valide après l'édition.
if bash -n "$HOOK" 2>/dev/null; then
	ok "le hook 0500 garde une syntaxe shell valide"
else
	non "le hook 0500 ne se parse plus :\n$(bash -n "$HOOK" 2>&1 | head -3)"
fi

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[[ "$ECHOUES" -eq 0 ]]
