# Outils d’audit : catégories et images

Le lanceur s’appelle **Outils d’audit**. Le bouton du Terminal Pro et la
tuile du tableau de bord ouvrent le menu graphique existant, avec recherche,
sept catégories accompagnées d’emojis et boutons explicites **Terminal**,
**Ouvrir** et **Commandes**. Accès direct : `lexos audit menu`.
`lexos audit` conserve le navigateur texte.

Les images sont disponibles hors ligne : 48 SVG du paquet officiel
`kali-menu_2026.3.4.tar.xz`, vérifié par SHA-256 avant extraction.
Les images correspondent aux outils du manifeste existant ; pour les autres,
le menu conserve l’icône du système. Aucune image officielle n’est inventée.
La provenance, les empreintes et la licence GPL-3.0+ sont dans
`/usr/share/doc/lexos-audit-icons/`. Les fichiers originaux ne sont pas retouchés.

La fiche de l’outil en console commence en haut du terminal avec son image,
rendue en blocs de couleur compatibles avec le terminal, son nom et jusqu’à
huit commandes. La liste complète reste accessible par **Commandes**.
L’aide longue n’est plus lancée automatiquement, pour garder l’image visible.
Le shell reste interactif ; l’utilisateur choisit les commandes à exécuter.
Cette image n’est pas un bandeau fixe : elle défile avec la sortie du terminal.

Les paquets et leur installation dans l’ISO ne sont pas modifiés.
Les modifications concernent les sources ; aucune ISO n’a été reconstruite
et aucune application système installée n’a été mise à jour dans cette session.

## Vérification

46 tests réussis : catalogue, images, correspondance aux outils, affichage du
bandeau, fiche courte et branchements du tableau de bord. Un test GTK est
ignoré faute d’affichage disponible. Syntaxe JavaScript du Terminal Pro,
syntaxe du répartiteur Bash et `git diff --check` vérifiés.
La fluidité visuelle et les clics doivent encore être essayés sur le bureau réel.

## Auto-évaluation

| Axe | Note | Preuve et limite |
|---|---|---|
| Exactitude | 4/5 | Archive vérifiée et images validées ; rendu GTK non essayé. |
| Complétude | 4/5 | Menu et terminal branchés ; 52 outils sans image correspondante dans cette archive utilisent un repli. |
| Clarté | 4/5 | Boutons explicites et catégories lisibles ; lisibilité des emojis à vérifier sur le bureau. |
| Action | 4/5 | Sources et images prêtes pour la construction ; version installée non mise à jour. |
| Concision | 4/5 | Fiche courte ; toutes les commandes accessibles séparément. |

Moyenne : 4,0/5. Priorités : essayer le menu sur le bureau, puis construire
et vérifier l’ISO. Auto-contrôle : ce bilan distingue les tests réussis de la
fluidité non mesurée et les images authentiques des icônes de repli.
