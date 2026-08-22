#!/bin/sh
# =============================================================================
#  build-site.sh — assemble le site LexOS dans _site/
# =============================================================================
#  UN SEUL SCRIPT, DEUX HÉBERGEURS.
#  GitHub Pages et Vercel publient le même site. S'ils avaient chacun leur
#  recette, l'une des deux finirait par prendre du retard sans que personne
#  s'en aperçoive — jusqu'au jour où l'adresse qu'on donne aux gens montre
#  une version d'il y a trois semaines. Les deux appellent donc ce fichier.
#
#  POURQUOI IL FAUT ASSEMBLER PLUTÔT QUE PUBLIER LE DÉPÔT TEL QUEL
#  · Le site vit dans website/, pas à la racine. Publier la racine donne un
#    404 : il n'y a pas d'index.html au premier niveau. C'est exactement
#    l'erreur qu'a affichée Vercel au premier essai.
#  · Les pages écrivent « ../branding/logo… », parce qu'elles sont à côté du
#    dossier branding DANS LE DÉPÔT. Une fois le site à la racine du domaine,
#    ce « ../ » sort du site publié et le logo disparaît.
#  · branding/ pèse 12 Mo (mascottes animées, affiches). Le site n'a besoin
#    que d'UNE image de 30 Ko. On copie fichier par fichier.
#  · La démo du bureau est un fichier unique de 4 Mo, autonome. Elle va dans
#    /demo/ pour avoir une adresse propre.
# =============================================================================
set -e

SORTIE="${1:-_site}"

rm -rf "$SORTIE"
mkdir -p "$SORTIE/branding" "$SORTIE/demo"

cp -r website/. "$SORTIE/"
cp branding/logo-ti-lex-al-icon.png "$SORTIE/branding/"
sed -i 's|\.\./branding/|branding/|g' "$SORTIE"/*.html
cp web-demo/index.html "$SORTIE/demo/index.html"

#  .nojekyll : sans lui, GitHub ignore les fichiers et dossiers commençant
#  par un souligné. Rien n'en porte aujourd'hui — c'est le genre de piège
#  qu'on ne découvre qu'après. Vercel s'en moque, ça ne le gêne pas.
touch "$SORTIE/.nojekyll"

echo "── Contrôles ─────────────────────────────"
test -s "$SORTIE/index.html"      || { echo "ERREUR : index.html manquant" >&2; exit 1; }
test -s "$SORTIE/demo/index.html" || { echo "ERREUR : la démo est absente" >&2; exit 1; }
test -s "$SORTIE/branding/logo-ti-lex-al-icon.png" \
	|| { echo "ERREUR : le logo est absent" >&2; exit 1; }

#  Plus aucun « ../ » ne doit rester : ce serait une image morte, et une
#  image morte ne se voit que si quelqu'un regarde la page. On préfère un
#  échec bruyant maintenant.
if grep -rl '\.\./branding' "$SORTIE"/ 2>/dev/null | grep -q .; then
	echo "ERREUR : des chemins « ../branding » n'ont pas été corrigés" >&2
	grep -rn '\.\./branding' "$SORTIE"/ | head >&2
	exit 1
fi

echo "Pages publiées :"
find "$SORTIE" -maxdepth 2 -name '*.html' | sort | sed 's/^/  /'
echo "Poids total : $(du -sh "$SORTIE" | cut -f1)"
