# LexOS — diagnostic partagé Secure Boot (POSIX, lecture seule).
# Debian signe shim/GRUB/noyau. DKMS peut signer avec une MOK locale;
# signature et confiance sont distinctes. Conserver Secure Boot actif.
# Le diagnostic ne change ni NVRAM, ni partitions, ni démarrage Windows.
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
		echo "SECURE BOOT : ACTIF — conserver ce réglage pour Windows."
		echo "Un module NVIDIA DKMS peut être signé avec une clé locale non reconnue."
		echo "Cet état seul ne prouve pas la cause d'un écran noir."
		if command -v lexos-signer-pilote >/dev/null 2>&1; then
			echo "Diagnostic sans changement : lexos-signer-pilote --etat"
			echo "Sur LexOS installé : sudo lexos-signer-pilote propose l'inscription MOK."
		fi
		echo "En live RTX 5060 : utiliser le mode secours si NVIDIA n'est pas accepté."
		echo "Ne pas désactiver Secure Boot ni modifier les clés UEFI pour contourner."
		echo "Conserver la clé de récupération BitLocker avant tout changement de démarrage."
		echo "Les jeux avec anti-triche peuvent exiger Secure Boot actif."
	else
		echo "Secure Boot : inactif — aucune validation de signature imposée par ce réglage."
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
