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
#  Les deux racines se détournent par une variable. Ce n'est pas de la
#  souplesse gratuite : sans ça, ces fonctions ne sont éprouvables NULLE PART.
#  /sys et /dev ne se fabriquent pas dans un banc d'essai, et un contrôle qu'on
#  ne peut que relire finit par mentir — c'est la leçon de verifier.sh, qui a
#  passé des mois à ne rien vérifier sans que ça se voie.
LEXOS_EFIVARS="${LEXOS_EFIVARS:-/sys/firmware/efi/efivars}"
LEXOS_DEV="${LEXOS_DEV:-/dev}"

secure_boot_actif() {
	for _sb_f in "$LEXOS_EFIVARS"/SecureBoot-*; do
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

# =============================================================================
#  L'AUTRE RÉGLAGE DU BIOS QUI FAIT PASSER LA MACHINE POUR CASSÉE
# =============================================================================
#  Dell et Alienware livrent leurs machines en « RAID On » : le disque NVMe
#  passe derrière un contrôleur Intel RST/VMD, que Linux ne sait pas ouvrir
#  sans configuration. Le symptôme est brutal et MUET — LexOS démarre très
#  bien depuis la clé USB, le bureau s'ouvre, tout va bien… et l'installateur
#  affiche une liste de disques VIDE. Pas d'erreur, pas de message. On cherche
#  du côté du disque, du câble, de la partition, alors que le disque va bien.
#
#  DEUX CONDITIONS, ET PAS UNE. Ne voir aucun NVMe ne prouve rien : beaucoup
#  de machines n'en ont tout simplement pas. Voir un contrôleur RAID ne prouve
#  rien non plus. C'est la CONJONCTION qui est parlante — un contrôleur de ce
#  type présent, et pas un seul disque NVMe derrière lui.
#
#  POSIX PUR, comme tout ce fichier : lexos-tv est en #!/bin/sh.

#  Un disque NVMe est-il visible ? Le motif est développé par le SHELL, pas
#  par « ls » : sans correspondance il reste littéral, « [ -e ] » échoue
#  dessus, et la boucle se termine — le cas « aucun disque » se traite tout
#  seul, sans se souvenir de tester une chaîne vide.
nvme_visible() {
	for _nv_d in "$LEXOS_DEV"/nvme*n1; do
		[ -e "$_nv_d" ] && return 0
	done
	return 1
}

#  Rend 0 (vrai) quand le mode RAID est PROBABLE. Le mot compte : on ne peut
#  pas lire le réglage du BIOS depuis Linux, seulement constater ses effets.
#  Sans lspci on rend 1 — mais « mode_raid_dire » distingue alors « non » de
#  « je ne peux pas savoir », parce qu'un contrôle qui ne contrôle rien tout
#  en ayant l'air de contrôler est pire que pas de contrôle du tout.
mode_raid_probable() {
	nvme_visible && return 1
	command -v lspci >/dev/null 2>&1 || return 1
	lspci 2>/dev/null 		| grep -qiE 'volume management device|RAID bus controller'
}

mode_raid_dire() {
	if ! command -v lspci >/dev/null 2>&1; then
		echo "Mode du disque : impossible à vérifier (lspci absent, paquet pciutils)."
		return
	fi
	if mode_raid_probable; then
		echo "DISQUE EN MODE RAID : PROBABLE"
		echo
		echo "  Un contrôleur RAID/VMD est présent et aucun disque NVMe n'est"
		echo "  visible derrière lui. C'est le réglage d'usine de Dell et"
		echo "  d'Alienware, et Linux ne sait pas ouvrir le disque comme ça :"
		echo "  l'installateur affichera une liste de disques VIDE, sans dire"
		echo "  pourquoi. Le disque, lui, va très bien."
		echo
		echo "  Le remède :"
		echo "    1. Redémarrer, appuyer sur F2 au logo du fabricant"
		echo "    2. Storage (ou System Configuration)  ->  SATA/NVMe Operation"
		echo "    3. Passer de « RAID On » à « AHCI », enregistrer (F10)"
		echo
		echo "  ATTENTION SI WINDOWS EST ENCORE INSTALLÉ : ce changement"
		echo "  l'empêche de démarrer (écran bleu INACCESSIBLE_BOOT_DEVICE)."
		echo "  Pour garder les deux, dans Windows en administrateur :"
		echo "    bcdedit /set {current} safeboot minimal"
		echo "  redémarrer, passer en AHCI, laisser Windows démarrer une fois"
		echo "  en mode sans échec, puis :"
		echo "    bcdedit /deletevalue {current} safeboot"
	else
		echo "Mode du disque : rien d'anormal (pas de contrôleur RAID sans disque derrière)."
	fi
}
