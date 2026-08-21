"""Catalogue des optimisations de LexOS Boost.

Chaque optimisation est un objet Action qui sait trois choses :

  * si elle sert à quelque chose sur CETTE machine (pertinente),
  * comment s'appliquer en enregistrant de quoi revenir en arrière,
  * comment se défaire à partir de cet enregistrement.

Aucune action ne modifie le système sans avoir produit ses données de
restauration. Une action qui ne sait pas revenir en arrière ne doit pas
exister dans ce fichier.

Les niveaux :
  doux       — réglages sans effet visible sur le fonctionnement
  equilibre  — on touche au bureau, aux journaux, au montage disque
  max        — on coupe les services dont cette machine n'a pas besoin
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass, field

from . import systeme

NIVEAUX = ("doux", "equilibre", "max")


def niveau_atteint(niveau_demande: str, niveau_minimum: str) -> bool:
    """Le niveau demandé couvre-t-il ce minimum ?"""
    try:
        return NIVEAUX.index(niveau_demande) >= NIVEAUX.index(niveau_minimum)
    except ValueError:
        return False


@dataclass
class Resultat:
    """Ce qu'une action renvoie après avoir agi."""

    reussi: bool
    message: str
    restauration: dict = field(default_factory=dict)
    ignoree: bool = False  # vrai quand l'action n'avait rien à faire


class Action:
    """Classe de base. Toute optimisation en hérite."""

    identifiant: str = ""
    titre: str = ""
    explication: str = ""
    niveau_minimum: str = "doux"
    redemarrage_requis: bool = False

    # ------------------------------------------------------------- décision

    def pertinente(self, machine) -> tuple[bool, str]:
        """(utile ?, raison si non). Par défaut : toujours utile."""
        return True, ""

    def gain_estime(self, machine) -> str:
        """Phrase courte décrivant le bénéfice attendu."""
        return ""

    # ------------------------------------------------------------- exécution

    def appliquer(self, machine, reglages: dict, simulation: bool) -> Resultat:
        raise NotImplementedError

    def annuler(self, restauration: dict, simulation: bool) -> Resultat:
        raise NotImplementedError


# ==========================================================================
# 1. Réglages mémoire du noyau
# ==========================================================================

class SysctlMemoire(Action):
    identifiant = "sysctl_memoire"
    titre = "Réglages mémoire du noyau"
    explication = (
        "Change la façon dont Linux arbitre entre la mémoire vive et le "
        "disque. Sur une machine qui manque de RAM, c'est ce qui évite "
        "que tout se fige dès qu'on ouvre un deuxième onglet."
    )
    niveau_minimum = "doux"

    FICHIER = "/etc/sysctl.d/60-lexos-boost.conf"

    def gain_estime(self, machine) -> str:
        if machine.ram_mo < 4096:
            return "moins de blocages quand la mémoire se remplit"
        return "gain modeste, la machine a déjà assez de RAM"

    def appliquer(self, machine, reglages: dict, simulation: bool) -> Resultat:
        valeurs = reglages.get("sysctl", {})
        if not valeurs:
            return Resultat(True, "aucun réglage mémoire à appliquer", ignoree=True)

        capture = systeme.capturer_fichier(self.FICHIER)
        anciennes = {cle: systeme.lire_sysctl(cle) for cle in valeurs}

        lignes = [
            "# Écrit par LexOS Boost — ne pas modifier à la main.",
            "# Pour tout annuler : sudo lexos-boost --annuler",
            "",
        ]
        lignes += [f"{cle} = {valeur}" for cle, valeur in sorted(valeurs.items())]
        contenu = "\n".join(lignes) + "\n"

        if simulation:
            return Resultat(
                True,
                f"écrirait {len(valeurs)} réglage(s) dans {self.FICHIER}",
                {"fichier": capture, "anciennes": anciennes},
            )

        try:
            systeme.ecrire_fichier(self.FICHIER, contenu)
        except OSError as erreur:
            return Resultat(False, f"écriture impossible : {erreur}")

        appliques, echecs = 0, []
        for cle, valeur in valeurs.items():
            ok, message = systeme.ecrire_sysctl_direct(cle, str(valeur))
            if ok:
                appliques += 1
            else:
                echecs.append(message)

        message = f"{appliques}/{len(valeurs)} réglage(s) actifs immédiatement"
        if echecs:
            message += f" ({len(echecs)} refusé(s) par le noyau)"
        return Resultat(True, message, {"fichier": capture, "anciennes": anciennes})

    def annuler(self, restauration: dict, simulation: bool) -> Resultat:
        if simulation:
            return Resultat(True, f"retirerait {self.FICHIER} et remettrait les valeurs d'origine")

        ok, message = systeme.restaurer_fichier(restauration.get("fichier", {}))
        for cle, valeur in (restauration.get("anciennes") or {}).items():
            if valeur is not None:
                systeme.ecrire_sysctl_direct(cle, str(valeur))
        return Resultat(ok, message)


# ==========================================================================
# 2. zram — de la mémoire compressée au lieu du disque
# ==========================================================================

class Zram(Action):
    identifiant = "zram"
    titre = "Mémoire compressée (zram)"
    explication = (
        "Crée une zone d'échange compressée directement dans la RAM. "
        "Au lieu d'écrire sur un disque lent quand la mémoire est pleine, "
        "la machine compresse à la volée. C'est le gain le plus net sur "
        "un vieil ordinateur avec peu de mémoire et un disque mécanique."
    )
    niveau_minimum = "doux"

    CONF = "/etc/lexos/zram.conf"
    UNITE = "lexos-zram.service"

    def pertinente(self, machine) -> tuple[bool, str]:
        if machine.zram_actif:
            return False, "zram est déjà actif sur cette machine"
        if machine.ram_mo >= 16384:
            return False, "16 Go de RAM ou plus : zram n'apporterait rien"
        if not systeme.commande_existe("zramctl"):
            return False, "zramctl absent (paquet util-linux)"
        return True, ""

    def gain_estime(self, machine) -> str:
        if machine.ram_mo < 2048:
            return "très net : la machine cesse de ramer dès 2-3 applications"
        if machine.ram_mo < 4096:
            return "net, surtout avec un navigateur ouvert"
        return "modéré"

    def appliquer(self, machine, reglages: dict, simulation: bool) -> Resultat:
        taille_mo = reglages.get("zram_taille_mo", 0)
        algo = reglages.get("zram_algo", "zstd")
        if taille_mo <= 0:
            return Resultat(True, "zram non retenu pour cette machine", ignoree=True)

        capture = systeme.capturer_fichier(self.CONF)
        etat = systeme.etat_unite(self.UNITE) if systeme.systemd_present() else {}

        contenu = (
            "# Écrit par LexOS Boost — ne pas modifier à la main.\n"
            f"TAILLE_MO={taille_mo}\n"
            f"ALGO={algo}\n"
        )

        if simulation:
            return Resultat(
                True,
                f"créerait {taille_mo} Mo de mémoire compressée ({algo})",
                {"fichier": capture, "unite": etat},
            )

        try:
            systeme.ecrire_fichier(self.CONF, contenu)
        except OSError as erreur:
            return Resultat(False, f"écriture impossible : {erreur}")

        if not systeme.systemd_present():
            return Resultat(
                True,
                f"configuration écrite ({taille_mo} Mo) — sera active au prochain démarrage",
                {"fichier": capture, "unite": etat},
            )

        if not systeme.unite_existe(self.UNITE):
            return Resultat(
                False,
                f"{self.UNITE} introuvable : le paquet LexOS Boost est incomplet",
            )

        code, _, erreur = systeme.executer(["systemctl", "enable", "--now", self.UNITE], delai=60)
        if code != 0:
            systeme.restaurer_fichier(capture)
            return Resultat(False, f"activation refusée : {erreur or 'échec'}")

        return Resultat(
            True,
            f"{taille_mo} Mo de mémoire compressée actifs ({algo})",
            {"fichier": capture, "unite": etat},
        )

    def annuler(self, restauration: dict, simulation: bool) -> Resultat:
        if simulation:
            return Resultat(True, "désactiverait la mémoire compressée")

        messages = []
        if systeme.systemd_present() and systeme.unite_existe(self.UNITE):
            systeme.executer(["systemctl", "disable", "--now", self.UNITE], delai=60)
            messages.append("service arrêté")
        ok, message = systeme.restaurer_fichier(restauration.get("fichier", {}))
        messages.append(message)
        return Resultat(ok, " · ".join(messages))


# ==========================================================================
# 3. Gouverneur du processeur
# ==========================================================================

class GouverneurCpu(Action):
    identifiant = "gouverneur_cpu"
    titre = "Réactivité du processeur"
    explication = (
        "Décide à quelle vitesse le processeur monte en fréquence quand on "
        "lui demande quelque chose. Sur un ordinateur de bureau, on peut le "
        "laisser réagir à fond. Sur un portable, on garde un mode qui "
        "ménage la batterie."
    )
    niveau_minimum = "doux"

    BASE = "/sys/devices/system/cpu"

    def pertinente(self, machine) -> tuple[bool, str]:
        if not machine.gouverneurs_disponibles:
            return False, "ce processeur n'expose pas de gouverneur réglable"
        return True, ""

    def gain_estime(self, machine) -> str:
        return "les applications s'ouvrent plus vite, surtout au premier clic"

    def _processeurs(self) -> list[str]:
        try:
            entrees = os.listdir(self.BASE)
        except OSError:
            return []
        return sorted(
            e for e in entrees
            if re.fullmatch(r"cpu\d+", e)
            and os.path.exists(f"{self.BASE}/{e}/cpufreq/scaling_governor")
        )

    def appliquer(self, machine, reglages: dict, simulation: bool) -> Resultat:
        vise = reglages.get("gouverneur")
        if not vise:
            return Resultat(True, "aucun gouverneur à changer", ignoree=True)
        if vise not in machine.gouverneurs_disponibles:
            return Resultat(
                True,
                f"« {vise} » non disponible sur ce processeur",
                ignoree=True,
            )

        processeurs = self._processeurs()
        anciens = {
            cpu: systeme.lire_sysfs(f"{self.BASE}/{cpu}/cpufreq/scaling_governor")
            for cpu in processeurs
        }

        if simulation:
            return Resultat(
                True,
                f"passerait {len(processeurs)} cœur(s) en mode « {vise} »",
                {"anciens": anciens, "vise": vise},
            )

        changes = 0
        for cpu in processeurs:
            ok, _ = systeme.ecrire_sysfs(f"{self.BASE}/{cpu}/cpufreq/scaling_governor", vise)
            if ok:
                changes += 1

        if changes == 0:
            return Resultat(False, "le noyau a refusé le changement de gouverneur")
        return Resultat(
            True,
            f"{changes} cœur(s) en mode « {vise} »",
            {"anciens": anciens, "vise": vise},
        )

    def annuler(self, restauration: dict, simulation: bool) -> Resultat:
        anciens = restauration.get("anciens") or {}
        if simulation:
            return Resultat(True, f"remettrait le gouverneur d'origine sur {len(anciens)} cœur(s)")
        remis = 0
        for cpu, valeur in anciens.items():
            if valeur:
                ok, _ = systeme.ecrire_sysfs(f"{self.BASE}/{cpu}/cpufreq/scaling_governor", valeur)
                remis += 1 if ok else 0
        return Resultat(True, f"gouverneur d'origine remis sur {remis} cœur(s)")


# ==========================================================================
# 4. Anticipation de lecture du disque
# ==========================================================================

class ReadaheadDisque(Action):
    identifiant = "readahead_disque"
    titre = "Anticipation de lecture du disque"
    explication = (
        "Demande au disque de lire un peu plus loin que ce qu'on lui a "
        "demandé, en pariant que la suite sera utile. Sur un disque "
        "mécanique, ça réduit le nombre d'allers-retours de la tête de "
        "lecture — c'est ce qui fait le bruit et l'attente."
    )
    niveau_minimum = "doux"

    def pertinente(self, machine) -> tuple[bool, str]:
        if machine.disque_type not in ("hdd", "emmc", "inconnu"):
            return False, "utile surtout sur disque mécanique ou eMMC"
        if not machine.disque:
            return False, "disque système non identifié"
        return True, ""

    def gain_estime(self, machine) -> str:
        return "démarrage et ouverture des gros logiciels plus rapides"

    def appliquer(self, machine, reglages: dict, simulation: bool) -> Resultat:
        kio = reglages.get("readahead_kio")
        if not kio or not machine.disque:
            return Resultat(True, "anticipation de lecture inchangée", ignoree=True)

        chemin = f"/sys/block/{machine.disque}/queue/read_ahead_kb"
        ancien = systeme.lire_sysfs(chemin)
        if ancien is None:
            return Resultat(True, "ce disque n'expose pas ce réglage", ignoree=True)

        # On ne descend jamais une valeur déjà meilleure. Certains noyaux et
        # certaines cartes RAID règlent l'anticipation bien plus haut que nous :
        # l'écraser dégraderait la machine au lieu de l'améliorer.
        try:
            if int(ancien) >= int(kio):
                return Resultat(
                    True,
                    f"anticipation déjà à {ancien} Kio, mieux que les {kio} Kio visés",
                    ignoree=True,
                )
        except (TypeError, ValueError):
            pass

        if simulation:
            return Resultat(
                True,
                f"passerait l'anticipation de {ancien} à {kio} Kio",
                {"chemin": chemin, "ancien": ancien, "vise": str(kio)},
            )

        ok, message = systeme.ecrire_sysfs(chemin, str(kio))
        if not ok:
            return Resultat(False, message)
        return Resultat(
            True,
            f"anticipation de lecture portée à {kio} Kio",
            {"chemin": chemin, "ancien": ancien, "vise": str(kio)},
        )

    def annuler(self, restauration: dict, simulation: bool) -> Resultat:
        chemin, ancien = restauration.get("chemin"), restauration.get("ancien")
        if simulation:
            return Resultat(True, f"remettrait l'anticipation à {ancien} Kio")
        if not chemin or ancien is None:
            return Resultat(False, "valeur d'origine non enregistrée")
        ok, message = systeme.ecrire_sysfs(chemin, str(ancien))
        return Resultat(ok, message or f"anticipation remise à {ancien} Kio")


# ==========================================================================
# 5. Ordonnanceur d'entrées/sorties
# ==========================================================================

class OrdonnanceurDisque(Action):
    identifiant = "ordonnanceur_disque"
    titre = "File d'attente du disque"
    explication = (
        "Choisit l'algorithme qui décide dans quel ordre le disque traite "
        "les demandes. Sur un disque mécanique, le bon choix empêche qu'un "
        "gros téléchargement bloque tout le reste de la machine."
    )
    niveau_minimum = "equilibre"

    def pertinente(self, machine) -> tuple[bool, str]:
        if not machine.disque or not machine.ordonnanceurs_disponibles:
            return False, "disque système non identifié"
        return True, ""

    def gain_estime(self, machine) -> str:
        if machine.disque_type == "hdd":
            return "la machine reste utilisable pendant les grosses copies"
        return "léger, le disque est déjà rapide"

    def appliquer(self, machine, reglages: dict, simulation: bool) -> Resultat:
        vise = reglages.get("ordonnanceur")
        if not vise or not machine.disque:
            return Resultat(True, "file d'attente inchangée", ignoree=True)
        if vise not in machine.ordonnanceurs_disponibles:
            return Resultat(True, f"« {vise} » non disponible sur ce disque", ignoree=True)

        chemin = f"/sys/block/{machine.disque}/queue/scheduler"
        ancien = machine.ordonnanceur_actif

        if simulation:
            return Resultat(
                True,
                f"passerait la file d'attente de « {ancien} » à « {vise} »",
                {"chemin": chemin, "ancien": ancien, "vise": vise},
            )

        ok, message = systeme.ecrire_sysfs(chemin, vise)
        if not ok:
            return Resultat(False, message)
        return Resultat(
            True,
            f"file d'attente du disque en « {vise} »",
            {"chemin": chemin, "ancien": ancien, "vise": vise},
        )

    def annuler(self, restauration: dict, simulation: bool) -> Resultat:
        chemin, ancien = restauration.get("chemin"), restauration.get("ancien")
        if simulation:
            return Resultat(True, f"remettrait la file d'attente en « {ancien} »")
        if not chemin or not ancien:
            return Resultat(False, "valeur d'origine non enregistrée")
        ok, message = systeme.ecrire_sysfs(chemin, ancien)
        return Resultat(ok, message or f"file d'attente remise en « {ancien} »")


# ==========================================================================
# 6. Taille des journaux système
# ==========================================================================

class JournalSystemd(Action):
    identifiant = "journal_systemd"
    titre = "Taille des journaux système"
    explication = (
        "Linux garde l'historique de tout ce qui se passe. Sur un petit "
        "disque, ces journaux finissent par occuper plusieurs gigaoctets "
        "sans que personne ne les lise jamais. On plafonne, on ne supprime "
        "pas la fonction."
    )
    niveau_minimum = "equilibre"

    FICHIER = "/etc/systemd/journald.conf.d/60-lexos-boost.conf"

    def pertinente(self, machine) -> tuple[bool, str]:
        if not machine.systemd:
            return False, "systemd absent"
        return True, ""

    def gain_estime(self, machine) -> str:
        return "récupère souvent 1 à 3 Go sur un disque déjà plein"

    def appliquer(self, machine, reglages: dict, simulation: bool) -> Resultat:
        plafond = reglages.get("journal_max_mo")
        if not plafond:
            return Resultat(True, "journaux inchangés", ignoree=True)

        capture = systeme.capturer_fichier(self.FICHIER)
        contenu = (
            "# Écrit par LexOS Boost — ne pas modifier à la main.\n"
            "[Journal]\n"
            f"SystemMaxUse={plafond}M\n"
            f"RuntimeMaxUse={max(plafond // 4, 16)}M\n"
        )

        if simulation:
            return Resultat(
                True,
                f"plafonnerait les journaux à {plafond} Mo",
                {"fichier": capture},
            )

        try:
            systeme.ecrire_fichier(self.FICHIER, contenu)
        except OSError as erreur:
            return Resultat(False, f"écriture impossible : {erreur}")

        libere = ""
        code, sortie, _ = systeme.executer(["journalctl", f"--vacuum-size={plafond}M"], delai=120)
        if code == 0 and sortie:
            derniere = sortie.strip().splitlines()[-1]
            libere = f" ({derniere})"
        systeme.executer(["systemctl", "restart", "systemd-journald"], delai=60)

        return Resultat(True, f"journaux plafonnés à {plafond} Mo{libere}", {"fichier": capture})

    def annuler(self, restauration: dict, simulation: bool) -> Resultat:
        if simulation:
            return Resultat(True, "retirerait le plafond sur les journaux")
        ok, message = systeme.restaurer_fichier(restauration.get("fichier", {}))
        systeme.executer(["systemctl", "restart", "systemd-journald"], delai=60)
        return Resultat(ok, message)


# ==========================================================================
# 7. noatime — arrêter d'écrire à chaque lecture
# ==========================================================================

class Noatime(Action):
    identifiant = "noatime"
    titre = "Moins d'écritures inutiles sur le disque"
    explication = (
        "Par défaut, Linux note la date du dernier accès à chaque fichier "
        "qu'on ouvre — donc il écrit sur le disque même quand on ne fait "
        "que lire. Presque aucun logiciel ne se sert de cette date. On "
        "l'arrête : moins d'usure sur un SSD, moins d'attente sur un "
        "disque mécanique."
    )
    niveau_minimum = "equilibre"
    redemarrage_requis = False

    FSTAB = "/etc/fstab"

    def pertinente(self, machine) -> tuple[bool, str]:
        if machine.live_usb:
            return False, "session live : le disque n'est pas monté en écriture"
        if not os.path.exists(self.FSTAB):
            return False, "/etc/fstab absent"
        contenu = systeme.capturer_fichier(self.FSTAB).get("contenu", "")
        ligne = self._ligne_racine(contenu)
        if ligne is None:
            return False, "aucune ligne pour / trouvée dans /etc/fstab"
        if "noatime" in ligne.split()[3]:
            return False, "déjà actif"
        return True, ""

    @staticmethod
    def _ligne_racine(contenu: str) -> str | None:
        """Ligne de /etc/fstab qui décrit le montage de la racine."""
        for ligne in contenu.splitlines():
            nue = ligne.strip()
            if not nue or nue.startswith("#"):
                continue
            morceaux = nue.split()
            if len(morceaux) >= 4 and morceaux[1] == "/":
                return nue
        return None

    def gain_estime(self, machine) -> str:
        if machine.disque_type == "hdd":
            return "navigation dans les dossiers plus fluide"
        return "moins d'usure du SSD"

    def appliquer(self, machine, reglages: dict, simulation: bool) -> Resultat:
        capture = systeme.capturer_fichier(self.FSTAB)
        contenu = capture.get("contenu")
        if contenu is None:
            return Resultat(False, "/etc/fstab illisible")

        ancienne = self._ligne_racine(contenu)
        if ancienne is None:
            return Resultat(True, "aucune ligne racine à modifier", ignoree=True)

        morceaux = ancienne.split()
        options = [o for o in morceaux[3].split(",") if o]
        if "noatime" in options:
            return Resultat(True, "déjà actif", ignoree=True)

        # noatime implique nodiratime ; relatime devient inutile
        options = [o for o in options if o not in ("atime", "relatime", "strictatime")]
        options.insert(1 if len(options) > 1 else len(options), "noatime")
        morceaux[3] = ",".join(options)
        nouvelle = "\t".join(morceaux) if "\t" in ancienne else " ".join(morceaux)
        nouveau_contenu = contenu.replace(ancienne, nouvelle, 1)

        if simulation:
            return Resultat(
                True,
                f"ajouterait « noatime » au montage de / (options : {morceaux[3]})",
                {"fichier": capture},
            )

        copie = systeme.copie_de_securite(self.FSTAB)
        try:
            systeme.ecrire_fichier(self.FSTAB, nouveau_contenu)
        except OSError as erreur:
            return Resultat(False, f"écriture impossible : {erreur}")

        code, _, erreur = systeme.executer(["mount", "-o", "remount", "/"], delai=30)
        message = "« noatime » activé sur /"
        if code != 0:
            message += " — actif au prochain démarrage (remontage à chaud refusé)"
        if copie:
            message += f" · copie de /etc/fstab dans {copie}"
        return Resultat(True, message, {"fichier": capture, "copie": copie})

    def annuler(self, restauration: dict, simulation: bool) -> Resultat:
        if simulation:
            return Resultat(True, "remettrait /etc/fstab dans son état d'origine")
        ok, message = systeme.restaurer_fichier(restauration.get("fichier", {}))
        if ok:
            systeme.executer(["mount", "-o", "remount", "/"], delai=30)
        return Resultat(ok, message)


# ==========================================================================
# 8. Effets visuels du bureau
# ==========================================================================

class EffetsBureau(Action):
    identifiant = "effets_bureau"
    titre = "Effets visuels du bureau"
    explication = (
        "Les ombres, les transparences et les animations des fenêtres sont "
        "calculées par la carte graphique. Sur une machine ancienne, c'est "
        "souvent le processeur qui s'en charge à sa place, et tout devient "
        "saccadé. On les coupe : le bureau reste le même, il répond juste "
        "au doigt et à l'œil."
    )
    niveau_minimum = "equilibre"

    REGLAGES = (
        ("xfwm4", "/general/use_compositing", "false"),
        ("xfwm4", "/general/box_move", "true"),
        ("xfwm4", "/general/box_resize", "true"),
        ("xfce4-desktop", "/desktop-icons/style", "0"),
    )

    def pertinente(self, machine) -> tuple[bool, str]:
        if not machine.session_graphique:
            return False, "aucune session graphique ouverte"
        if not systeme.commande_existe("xfconf-query"):
            return False, "bureau non XFCE"
        if machine.compositeur_actif is False:
            return False, "les effets sont déjà désactivés"
        return True, ""

    def gain_estime(self, machine) -> str:
        return "fenêtres qui répondent instantanément au lieu de traîner"

    def appliquer(self, machine, reglages: dict, simulation: bool) -> Resultat:
        if not reglages.get("couper_effets"):
            return Resultat(True, "effets visuels conservés", ignoree=True)

        anciens = []
        for canal, propriete, _ in self.REGLAGES:
            code, sortie, _ = systeme.xfconf(["-c", canal, "-p", propriete])
            anciens.append({
                "canal": canal,
                "propriete": propriete,
                "valeur": sortie.strip() if code == 0 else None,
            })

        if simulation:
            return Resultat(
                True,
                f"couperait {len(self.REGLAGES)} effet(s) visuel(s)",
                {"anciens": anciens},
            )

        changes = 0
        for canal, propriete, valeur in self.REGLAGES:
            code, _, _ = systeme.xfconf(
                ["-c", canal, "-p", propriete, "-s", valeur, "--create", "-t", "string"]
                if valeur not in ("true", "false")
                else ["-c", canal, "-p", propriete, "-s", valeur, "--create", "-t", "bool"]
            )
            changes += 1 if code == 0 else 0

        if changes == 0:
            return Resultat(False, "xfconf n'a accepté aucun changement")
        return Resultat(True, f"{changes} effet(s) visuel(s) coupé(s)", {"anciens": anciens})

    def annuler(self, restauration: dict, simulation: bool) -> Resultat:
        anciens = restauration.get("anciens") or []
        if simulation:
            return Resultat(True, f"remettrait {len(anciens)} réglage(s) du bureau")
        remis = 0
        for entree in anciens:
            valeur = entree.get("valeur")
            if valeur is None:
                continue
            typage = "bool" if valeur in ("true", "false") else "string"
            code, _, _ = systeme.xfconf([
                "-c", entree["canal"], "-p", entree["propriete"],
                "-s", valeur, "--create", "-t", typage,
            ])
            remis += 1 if code == 0 else 0
        return Resultat(True, f"{remis} réglage(s) du bureau remis")


# ==========================================================================
# 9. Services dont cette machine n'a pas besoin
# ==========================================================================

class ServicesInutiles(Action):
    identifiant = "services_inutiles"
    titre = "Services inutiles sur cette machine"
    explication = (
        "Certains services tournent en permanence pour du matériel que la "
        "machine n'a pas : le Bluetooth sans puce Bluetooth, le service "
        "d'impression sans imprimante. On ne les coupe que si le matériel "
        "correspondant est réellement absent, et tout est réactivable."
    )
    niveau_minimum = "max"

    def pertinente(self, machine) -> tuple[bool, str]:
        if not machine.systemd:
            return False, "systemd absent"
        return True, ""

    def gain_estime(self, machine) -> str:
        return "quelques dizaines de Mo de RAM et un démarrage plus court"

    @staticmethod
    def candidats(machine) -> list[tuple[str, str]]:
        """Services désactivables, avec la raison. Rien n'est coupé à l'aveugle."""
        liste: list[tuple[str, str]] = []
        if not machine.a_bluetooth:
            liste.append(("bluetooth.service", "aucune puce Bluetooth détectée"))
        if not machine.a_imprimante_usb:
            liste.append(("cups.service", "aucune imprimante USB branchée"))
            liste.append(("cups-browsed.service", "aucune imprimante USB branchée"))
        liste.append(("ModemManager.service", "aucun modem mobile sur ce type de machine"))
        liste.append(("avahi-daemon.service", "découverte réseau locale, rarement utilisée"))
        return liste

    def appliquer(self, machine, reglages: dict, simulation: bool) -> Resultat:
        if not reglages.get("couper_services"):
            return Resultat(True, "aucun service à couper", ignoree=True)

        a_traiter = [
            (unite, raison) for unite, raison in self.candidats(machine)
            if systeme.unite_existe(unite)
        ]
        if not a_traiter:
            return Resultat(True, "aucun service inutile trouvé", ignoree=True)

        etats = []
        for unite, raison in a_traiter:
            etat = systeme.etat_unite(unite)
            etat["raison"] = raison
            etats.append(etat)

        actifs = [e for e in etats if e["active"] == "active" or e["activee"] == "enabled"]
        if not actifs:
            return Resultat(True, "ces services étaient déjà inactifs", ignoree=True)

        if simulation:
            details = ", ".join(f"{e['unite']} ({e['raison']})" for e in actifs)
            return Resultat(True, f"couperait : {details}", {"unites": actifs})

        coupes = []
        for etat in actifs:
            ok, _ = systeme.desactiver_unite(etat["unite"])
            if ok:
                coupes.append(etat["unite"])

        return Resultat(
            True,
            f"{len(coupes)} service(s) coupé(s) : {', '.join(coupes)}" if coupes
            else "aucun service n'a pu être coupé",
            {"unites": actifs},
        )

    def annuler(self, restauration: dict, simulation: bool) -> Resultat:
        unites = restauration.get("unites") or []
        if simulation:
            return Resultat(True, f"réactiverait {len(unites)} service(s)")
        remis = []
        for etat in unites:
            ok, _ = systeme.restaurer_unite(etat)
            if ok:
                remis.append(etat.get("unite", "?"))
        return Resultat(True, f"{len(remis)} service(s) réactivé(s) : {', '.join(remis)}")


# ==========================================================================
# 10. Génération des miniatures
# ==========================================================================

class MiniaturesFichiers(Action):
    identifiant = "miniatures"
    titre = "Aperçus des fichiers"
    explication = (
        "Le gestionnaire de fichiers fabrique un aperçu de chaque image et "
        "de chaque vidéo qu'il croise. Sur une machine lente, ouvrir un "
        "dossier de photos peut la bloquer une minute. On limite les "
        "aperçus aux petits fichiers."
    )
    niveau_minimum = "max"

    FICHIER = "/etc/xdg/tumbler/tumbler.rc"

    def pertinente(self, machine) -> tuple[bool, str]:
        if not machine.session_graphique:
            return False, "aucune session graphique ouverte"
        if machine.ram_mo >= 8192 and machine.disque_type in ("ssd", "nvme"):
            return False, "machine assez rapide pour générer les aperçus sans gêne"
        return True, ""

    def gain_estime(self, machine) -> str:
        return "les dossiers d'images s'ouvrent sans bloquer"

    def appliquer(self, machine, reglages: dict, simulation: bool) -> Resultat:
        limite_mo = reglages.get("miniatures_limite_mo")
        if not limite_mo:
            return Resultat(True, "aperçus inchangés", ignoree=True)

        capture = systeme.capturer_fichier(self.FICHIER)
        octets = int(limite_mo) * 1024 * 1024
        contenu = (
            "# Écrit par LexOS Boost — ne pas modifier à la main.\n"
            "[FfmpegThumbnailer]\n"
            "Disabled=false\n"
            f"MaxFileSize={octets}\n"
            "\n[PixbufThumbnailer]\n"
            "Disabled=false\n"
            f"MaxFileSize={octets}\n"
        )

        if simulation:
            return Resultat(
                True,
                f"limiterait les aperçus aux fichiers de moins de {limite_mo} Mo",
                {"fichier": capture},
            )

        try:
            systeme.ecrire_fichier(self.FICHIER, contenu)
        except OSError as erreur:
            return Resultat(False, f"écriture impossible : {erreur}")
        return Resultat(
            True,
            f"aperçus limités aux fichiers de moins de {limite_mo} Mo",
            {"fichier": capture},
        )

    def annuler(self, restauration: dict, simulation: bool) -> Resultat:
        if simulation:
            return Resultat(True, "remettrait les aperçus par défaut")
        ok, message = systeme.restaurer_fichier(restauration.get("fichier", {}))
        return Resultat(ok, message)


# ==========================================================================
# le catalogue
# ==========================================================================

CATALOGUE: list[Action] = [
    SysctlMemoire(),
    Zram(),
    GouverneurCpu(),
    ReadaheadDisque(),
    OrdonnanceurDisque(),
    JournalSystemd(),
    Noatime(),
    EffetsBureau(),
    ServicesInutiles(),
    MiniaturesFichiers(),
]

PAR_IDENTIFIANT: dict[str, Action] = {a.identifiant: a for a in CATALOGUE}


def action(identifiant: str) -> Action | None:
    return PAR_IDENTIFIANT.get(identifiant)
