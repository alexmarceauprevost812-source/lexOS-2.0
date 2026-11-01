"""Mon téléphone — la page (voir services/telephone.py pour le pourquoi).

Quatre cartes, dans l'ordre où on s'en sert :
    1. Mon téléphone   ce qui est connecté (KDE Connect, Android/adb)
    2. L'écran         le téléphone dans une fenêtre, contrôlé à la souris
    3. Envoyer         choisir des fichiers, ou les GLISSER sur la fenêtre
    4. Recevoir        le code QR de la boîte de réception, et le dossier
"""
from __future__ import annotations


from PySide6.QtCore import Qt
from PySide6.QtWidgets import (QFileDialog, QHBoxLayout, QLabel, QLineEdit,
                               QWidget)

from ...services import execution
from ...services import telephone as svc
from .. import theme, widgets


def _rangee(*elements) -> QWidget:
    boite = QWidget()
    boite.setAttribute(Qt.WA_StyledBackground, True)
    #  Sélecteur par nom : un « background » nu se propagerait aux boutons
    #  et effacerait l'orange des boutons principaux.
    boite.setObjectName("Rangee")
    boite.setStyleSheet("#Rangee { background: transparent; }")
    d = QHBoxLayout(boite)
    d.setContentsMargins(0, 4, 0, 0)
    d.setSpacing(10)
    for e in elements:
        d.addWidget(e)
    d.addStretch(1)
    return boite


def _aide(texte: str) -> QLabel:
    l = QLabel(texte)
    l.setObjectName("CarteDetail")
    l.setWordWrap(True)
    l.setTextInteractionFlags(Qt.TextSelectableByMouse)
    return l


class PageTelephone(widgets.Page):
    def __init__(self, parent=None):
        super().__init__(
            "Mon téléphone",
            "Ton téléphone sur l'ordi : voir et contrôler son écran, lui "
            "envoyer des fichiers, en recevoir. Les deux appareils doivent "
            "être sur le même Wi-Fi (ou branchés en USB pour l'écran).", parent)
        self.setAcceptDrops(True)
        self._etat = {}

        # 1. Ce qui est connecté ------------------------------------------
        self.carte_etat = widgets.Carte("Connecté", "reseau").sans_jauge().sans_courbe()
        self.btn_jumeler = widgets.bouton("Jumeler un téléphone (KDE Connect)", "parametres")
        self.btn_jumeler.clicked.connect(lambda: self._faire(svc.ouvrir_kde))
        self.btn_sonner = widgets.bouton("Faire sonner le téléphone", "son")
        self.btn_sonner.clicked.connect(lambda: self._faire(svc.sonner))
        self.btn_relire = widgets.bouton("Relire", "maj")
        self.btn_relire.clicked.connect(self.rafraichir)
        self.carte_etat.corps.addWidget(_rangee(self.btn_jumeler, self.btn_sonner, self.btn_relire))
        self.disposition.addWidget(self.carte_etat)

        # 2. L'écran du téléphone -----------------------------------------
        self.carte_ecran = widgets.Carte("L'écran du téléphone", "affichage").sans_jauge().sans_courbe()
        self.carte_ecran.valeur.hide()
        self.carte_ecran.detail.setText(
            "Le téléphone s'affiche dans une fenêtre : la souris et le clavier "
            "le contrôlent. Android seulement.")
        self.btn_ecran = widgets.bouton("Afficher l'écran du téléphone", "affichage", principal=True)
        self.btn_ecran.clicked.connect(lambda: self._faire(svc.afficher_ecran, relire=False))
        self.carte_ecran.corps.addWidget(_rangee(self.btn_ecran))
        self.adresse = QLineEdit()
        self.adresse.setPlaceholderText("Adresse IP du téléphone, ex. 192.168.1.42")
        self.adresse.setMinimumWidth(300)
        self.adresse.returnPressed.connect(self._wifi)
        self.btn_wifi = widgets.bouton("Connecter en Wi-Fi", "reseau")
        self.btn_wifi.clicked.connect(self._wifi)
        self.carte_ecran.corps.addWidget(_rangee(self.adresse, self.btn_wifi))
        self.carte_ecran.corps.addWidget(_aide(
            "Première fois : sur le téléphone, Paramètres → À propos → touche 7 fois "
            "« Numéro de build », puis Options pour les développeurs → active "
            "« Débogage USB ». Branche le câble et accepte la fenêtre sur le téléphone. "
            "Sans fil : active « Débogage sans fil » et écris l'adresse IP ci-dessus."))
        self.disposition.addWidget(self.carte_ecran)

        # 3. Envoyer -------------------------------------------------------
        self.carte_envoi = widgets.Carte("Envoyer au téléphone", "fichiers").sans_jauge().sans_courbe()
        self.carte_envoi.valeur.hide()
        self.carte_envoi.detail.setText(
            "Choisis des fichiers, ou glisse-les n'importe où sur cette fenêtre. "
            "Avec un téléphone jumelé (KDE Connect), ils partent directement ; "
            "sinon un code QR s'ouvre, à scanner avec l'appareil photo, sans appli.")
        self.btn_envoyer = widgets.bouton("Choisir des fichiers à envoyer…", "fichiers", principal=True)
        self.btn_envoyer.clicked.connect(self._choisir)
        self.carte_envoi.corps.addWidget(_rangee(self.btn_envoyer))
        self.disposition.addWidget(self.carte_envoi)

        # 4. Recevoir ------------------------------------------------------
        self.carte_recus = widgets.Carte("Recevoir du téléphone", "stockage").sans_jauge().sans_courbe()
        self.carte_recus.valeur.hide()
        self.btn_recevoir = widgets.bouton("Recevoir des photos et fichiers (code QR)", "reseau", principal=True)
        self.btn_recevoir.clicked.connect(lambda: self._faire(svc.recevoir, relire=False))
        self.btn_dossier = widgets.bouton("Ouvrir les fichiers reçus", "fichiers")
        self.btn_dossier.clicked.connect(self._ouvrir_recus)
        self.carte_recus.corps.addWidget(_rangee(self.btn_recevoir, self.btn_dossier))
        self.disposition.addWidget(self.carte_recus)

        self.disposition.addStretch(1)
        self.periodique(8000)

    # -- lecture ---------------------------------------------------------
    def rafraichir(self):
        widgets.en_fond(self, svc.etat, self._pret, lambda m: self.statut.echec(m))

    def _pret(self, e: dict):
        self._etat = e
        lignes = []
        if e["kde"]:
            lignes.append("KDE Connect : " + ", ".join(n for _, n in e["kde"]))
        elif e["kde_installe"]:
            lignes.append("KDE Connect : aucun téléphone jumelé et joignable "
                          "(installe « KDE Connect » sur le téléphone, même Wi-Fi).")
        else:
            lignes.append("KDE Connect n'est pas installé.")
        prets = e["adb_prets"]
        attente = [s for s, x in e["adb"] if x == "unauthorized"]
        if prets:
            lignes.append(f"Android (écran) : {len(prets)} prêt{'s' if len(prets) > 1 else ''} — "
                          + ", ".join(prets))
        elif attente:
            lignes.append("Android : accepte « Autoriser le débogage USB » sur le téléphone.")
        elif e["adb_installe"]:
            lignes.append("Android (écran) : aucun téléphone branché ou connecté en Wi-Fi.")
        n = len(e["kde"]) + len(prets)
        self.carte_etat.montrer(
            "Aucun téléphone" if n == 0 else ("1 téléphone" if n == 1 else f"{n} connexions"),
            "\n".join(lignes))
        self.carte_etat.valeur.setStyleSheet(
            f"color: {theme.VERT if n else theme.TEXTE_SECOND};")

        if e["kde"]:
            self.btn_sonner.setEnabled(True); self.btn_sonner.setToolTip("")
        else:
            widgets.eteindre(self.btn_sonner, "Il faut un téléphone jumelé avec KDE Connect.")
        if not e["kde_installe"]:
            widgets.eteindre(self.btn_jumeler, "KDE Connect n'est pas installé (paquet kdeconnect).")
        if e["scrcpy_installe"]:
            self.btn_ecran.setEnabled(True); self.btn_ecran.setToolTip("")
        else:
            widgets.eteindre(self.btn_ecran, "scrcpy n'est pas installé.")
        if not e["adb_installe"]:
            widgets.eteindre(self.btn_wifi, "adb n'est pas installé (paquet android-tools-adb).")
        if not e["partage_installe"]:
            widgets.eteindre(self.btn_recevoir, "lexos-share est introuvable.")
        self.carte_recus.detail.setText(
            "Un code QR s'ouvre : le téléphone le scanne et envoie ses photos depuis "
            f"son navigateur, sans appli. Ils arrivent dans {e['recus']}.")

    # -- actions ---------------------------------------------------------
    def _faire(self, fonction, *args, relire=True):
        self.statut.occupe("Un instant…")

        def fini(r):
            self.afficher_resultat(r)
            if relire:
                self.rafraichir()
        widgets.en_fond(self, fonction, fini, lambda m: self.statut.echec(m), *args)

    def _wifi(self):
        self._faire(svc.connecter_wifi, self.adresse.text())

    def _choisir(self):
        fichiers, _ = QFileDialog.getOpenFileNames(self, "Fichiers à envoyer au téléphone")
        if fichiers:
            self._faire(svc.envoyer, fichiers, relire=False)

    def _ouvrir_recus(self):
        dossier = svc.dossier_recus()
        try:
            dossier.mkdir(parents=True, exist_ok=True)
        except OSError as err:
            self.statut.echec(f"Dossier impossible à créer : {err}")
            return
        for outil in ("lexos-ouvrir", "xdg-open"):
            if execution.outil_present(outil):
                self.afficher_resultat(execution.lancer_detache([outil, str(dossier)]),
                                       f"Fichiers reçus : {dossier}")
                return
        self.statut.attention(f"Les fichiers reçus sont dans {dossier}")

    # -- glisser-déposer : glisser des fichiers = les envoyer ------------
    def dragEnterEvent(self, ev):
        if ev.mimeData().hasUrls():
            ev.acceptProposedAction()

    def dropEvent(self, ev):
        fichiers = [u.toLocalFile() for u in ev.mimeData().urls() if u.isLocalFile()]
        if fichiers:
            ev.acceptProposedAction()
            self._faire(svc.envoyer, fichiers, relire=False)
