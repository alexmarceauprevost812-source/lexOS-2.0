# LexOS Terminal Android — clone Termux, interface LexOS

Sources : https://github.com/termux/termux-app
Revision amont fixee : 8629e632fcb95da272221be327db653fb24befe9

## Prototype de l'interface

Depuis votre PC LexOS, dans ce dossier, lancer :

    bash clone-termux.sh "$HOME/lexos-termux-source"

La commande telecharge **le vrai code source de Termux**, puis applique une
interface sombre LexOS : nom LexOS Terminal, panneaux bleu nuit,
barre de touches bleue et espace tactile adapte. Le moteur Linux, les
commandes et les sessions restent ceux du projet amont.

## Avertissement IMPORTANT — APK non prete

Ce premier prototype conserve **com.termux** et les bootstraps de Termux.
Ne pas installer un binaire issu de ce dossier sur un telephone avec
Termux deja installe : signature/identifiant peuvent entrer en conflit,
et l'installation pourrait necessiter de supprimer l'application existante.

Pour une APK LexOS independante, il faut d'abord :
- donner un identifiant d'application LexOS distinct ;
- recompiler le bootstrap et les packages natifs pour ce nouvel identifiant ;
- adapter les constantes et integrations des modules Termux ;
- tester les sessions, les commandes, le clavier et les fichiers Android ;
- construire et signer la version Android, puis verifier les mises a jour.

Une simple modification de l'icône ou de l'applicationId ne suffit PAS :
le chemin PREFIX est compile dans des binaires Termux.

## Licence

Termux / termux-app est **GPL-3.0-only** (avec exceptions pour certaines
bibliotheques). Garder le fichier LICENSE.md et les notices du code amont,
ainsi que les licences des modules et des paquets. Le code source correspondant
aux binaires distribues devra etre mis a disposition.

Le projet LexOS n'est pas l'application officielle Termux. Les presentes
modifications d'interface sont partagees sous GPL-3.0-only.

## Suite du chantier

- Interface tactile avec onglets et panneau de sessions.
- Barre d'outils copier/coller et selection de fichiers.
- Champ de saisie au-dessus du clavier Samsung, toujours visible.
- SSH vers LexOS Pro via Tailscale, si l'utilisateur le configure.
- Propre identifiant Android et bootstrap independant.
- APK de test, verification sur S25 Ultra, signature et mises a jour.

Termux local : commandes executees sur le telephone.
LexOS Remote/SSH : commandes executees sur le PC.
