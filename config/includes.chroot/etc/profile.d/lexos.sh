# =============================================================================
#  LexOS — environnement de connexion
# =============================================================================
#  Ce fichier n'est plus qu'un chargeur. Le contenu (invite, alias, touche Tab,
#  logo d'accueil) vit dans /usr/share/lexos/shell/interactive.sh, parce que
#  /etc/profile.d n'est lu que par les shells de CONNEXION : le terminal du
#  bureau, lui, ne passe jamais par ici. Le hook 0120-lexos-terminal branche le
#  même fichier sur /etc/bash.bashrc, qui lui est lu par tous les shells
#  interactifs. Les deux chemins mènent au même endroit, et le fichier se
#  protège d'un double chargement.
# =============================================================================
# shellcheck shell=sh

if [ -r /usr/share/lexos/shell/interactive.sh ]; then
	# shellcheck disable=SC1091
	. /usr/share/lexos/shell/interactive.sh
fi
