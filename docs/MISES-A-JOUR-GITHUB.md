# Mettre LexOS Pro à jour sans réinstaller

Les logiciels Debian et le pilote NVIDIA restent mis à jour par leurs dépôts
APT configurés. L'interface et les commandes propres à LexOS sont livrées dans
le paquet `lexos-system`, publié dans la release GitHub `updates-pro`.

Dans Paramètres → Mises à jour, « Vérifier la version LexOS » consulte GitHub,
et « Mettre LexOS à jour sans réinstaller » télécharge et installe le paquet
avec APT. Le terminal affiche les demandes de mot de passe et de confirmation.
Il n'est pas nécessaire de recréer une clé USB ni de réinstaller Debian.
Un noyau ou pilote nouveau peut demander un redémarrage ; l'outil n'en lance pas.

Le premier paquet peut être installé sur un LexOS Pro déjà installé sur disque
avec `sudo apt install ./lexos-system_<version>_amd64.deb`, après téléchargement
depuis la release officielle. Il ajoute ensuite les boutons de mise à jour.
Une session live sans persistance ne conserve pas l'installation : l'outil y
refuse l'installation automatique. Il ne modifie ni les partitions ni Windows.

Chaque paquet conserve une version datée avec le commit source. L'outil compare
la version installée via dpkg et refuse les rétrogradations automatiques. Il
vérifie l'empreinte SHA-256 donnée par l'API HTTPS GitHub, la taille du fichier,
le nom du dépôt, puis le nom, la version et l'architecture du paquet. Ce contrôle
repose sur la confiance accordée au dépôt GitHub : ce n'est pas une signature
APT indépendante. Aucun téléchargement n'est exécuté via une commande shell.

La publication est manuelle par le workflow « Publier une mise à jour LexOS Pro ».
Les anciens paquets restent disponibles. Le paquet met à jour les fichiers
LexOS sous `/usr`, les icônes et le bouton autostart système ; les préférences
des utilisateurs et leurs fichiers personnels ne sont pas réécrits. Les deux
bureaux par défaut s'appliquent aux nouvelles installations ISO uniquement.
Après la première installation du paquet, le bouton fixe apparaît à la prochaine
connexion ; on peut aussi lancer `lexos-overview --dock-button` pour cette session.
