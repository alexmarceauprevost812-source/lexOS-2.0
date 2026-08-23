# =============================================================================
#  LexOS — Secure Boot : actif ou non ?
# =============================================================================
#  POURQUOI CE FICHIER EXISTE, ET POURQUOI IL EST À PART.
#
#  Deux outils ont besoin de cette réponse — « lexos materiel » et
#  « lexos tv » — et ils ne parlent pas le même shell : lexos-tv est en
#  #!/bin/sh, lexos-materiel en #!/usr/bin/env bash. Recopier six lignes dans
#  les deux, c'était s'exposer à ce qu'elles divergent : ce dépôt a déjà payé
#  ça cher avec les trois palettes des panneaux web, qui disaient trois choses
#  différentes de la même couleur.
#
#  D'où un seul fichier, en POSIX PUR. Ne pas le « moderniser » avec [[ ]],
#  un tableau ou une substitution bash : il cesserait de fonctionner dans
#  lexos-tv, et il cesserait EN SILENCE — la fonction deviendrait simplement
#  introuvable, et l'appelant conclurait « Secure Boot inactif ».
#
#  ═══ CE QUE ÇA CHANGE, ET POURQUOI ÇA COMPTE MAINTENANT ═══
#
#  Le module NVIDIA est compilé par DKMS sur la machine. Un module DKMS n'est
#  PAS signé. Avec Secure Boot actif, le noyau refuse de le charger.
#
#  Jusqu'au build 52, ça donnait un affichage dégradé. Depuis que le hook 0260
#  met « nouveau » en liste noire — et c'était la BONNE correction, il fallait
#  la faire, nouveau ne sait pas lire les sorties d'une RTX 50 — la situation
#  a changé :
#
#      Secure Boot actif  →  nvidia.ko refusé  →  nouveau en liste noire
#                         →  AUCUN pilote graphique du tout.
#
#  La liste noire a transformé une panne partielle en panne totale. C'est le
#  prix à payer et il est justifié, mais il faut le DIRE. Alex a désactivé
#  Secure Boot à la main sur son Alienware, donc ça marche pour lui
#  aujourd'hui ; une mise à jour du BIOS ou une pile CMOS à plat le
#  réactivent — les deux sont courants sur ces machines — et l'écran redevient
#  noir sans la moindre explication.
#
#  SIGNER LE MODULE N'EST PAS UNE OPTION ICI : inscrire une clé MOK demande
#  une manipulation au clavier pendant le démarrage, avant tout système.
#  Impossible depuis une ISO live. On ne le promet donc pas — on prévient.
# =============================================================================
#
#  Ce fragment est SOURCÉ, pas exécuté : pas de shebang, donc shellcheck ne
#  peut pas deviner le shell visé et refuse d'analyser (SC2148). On le lui
#  dit, comme dans interactive.sh juste à côté.
# shellcheck shell=sh

#  La variable EFI « SecureBoot » fait 5 octets : 4 d'attributs, puis la
#  valeur. Le cinquième vaut 1 quand Secure Boot est actif. On la lit
#  directement plutôt que d'appeler mokutil, qui n'est pas toujours installé —
#  et un diagnostic qui dépend d'un paquet optionnel finit par ne rien dire
#  le jour où on en a besoin.
#
#  Rend 0 (vrai) si Secure Boot est ACTIF. Rend 1 dans tous les autres cas :
#  machine en BIOS hérité, variable absente, fichier illisible. Le doute
#  penche donc vers « inactif » — on préfère ne rien dire à accuser Secure
#  Boot d'un écran noir dont il n'est pas responsable.
#  On développe le motif par le SHELL plutôt que par « ls ». Deux raisons :
#  pas de sous-processus, et surtout le cas « aucun fichier » se traite tout
#  seul — le motif reste alors littéral, « [ -r ] » échoue dessus, et la
#  boucle se termine sans rien dire. Avec « ls », il fallait se souvenir de
#  tester la chaîne vide.
secure_boot_actif() {
	for _sb_f in /sys/firmware/efi/efivars/SecureBoot-*; do
		[ -r "$_sb_f" ] || continue
		[ "$(od -An -t u1 "$_sb_f" 2>/dev/null | awk '{print $5}')" = "1" ] \
			&& return 0
		return 1
	done
	return 1
}

#  Le message, écrit une seule fois pour les deux outils. Il nomme la touche
#  et les trois étapes : quelqu'un devant un écran noir n'a pas envie de
#  chercher, il a envie qu'on lui dise quoi faire.
secure_boot_dire() {
	if secure_boot_actif; then
		echo "SECURE BOOT : ACTIF"
		echo
		echo "  C'est probablement la cause de ton écran noir."
		echo "  Le pilote NVIDIA de LexOS est compilé sur ta machine, et un"
		echo "  pilote compilé n'est pas signé : avec Secure Boot actif, le"
		echo "  noyau REFUSE de le charger. Et comme LexOS écarte volontairement"
		echo "  le pilote libre « nouveau » (il ne sait pas piloter les RTX 50),"
		echo "  il ne reste alors AUCUN pilote graphique."
		echo
		echo "  Le remède, une fois pour toutes :"
		echo "    1. Redémarrer, appuyer sur F2 au logo du fabricant"
		echo "    2. Boot  ->  Secure Boot  ->  Disabled"
		echo "    3. Enregistrer et quitter (F10)"
	else
		echo "Secure Boot : inactif — le pilote NVIDIA peut se charger."
	fi
}
