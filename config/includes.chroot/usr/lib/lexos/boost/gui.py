"""Panneau graphique de LexOS Boost.

Le panneau ne contient aucune logique d'optimisation : il analyse en
lecture seule avec le moteur, et délègue toute modification à
« pkexec lexos-boost », dont il affiche la sortie en direct.

Ce choix est délibéré. Une interface graphique qui tourne en root est
une interface graphique qu'on doit auditer entièrement ; ici, seule la
ligne de commande a les droits, et elle est la même que celle qu'un
utilisateur averti lancerait à la main.
"""

from __future__ import annotations

import sys

sys.path.insert(0, "/usr/lib/lexos")

import gi  # noqa: E402

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gio, GLib, Pango  # noqa: E402

from boost import __version__  # noqa: E402
from boost.actions import NIVEAUX  # noqa: E402
from boost.moteur import Moteur  # noqa: E402


DESCRIPTIONS = {
    "doux": (
        "Doux",
        "Réglages invisibles au quotidien. Aucun service coupé, "
        "aucun effet visuel retiré.",
    ),
    "equilibre": (
        "Équilibré",
        "On allège aussi le bureau et les journaux système. "
        "C'est le bon compromis sur la plupart des machines.",
    ),
    "max": (
        "LV MAX",
        "Le maximum de ce que CETTE machine peut donner. On coupe en plus "
        "les services dont ton matériel n'a pas besoin. Tout reste "
        "réversible d'un seul clic.",
    ),
}


class Fenetre(Gtk.ApplicationWindow):
    def __init__(self, application: Gtk.Application):
        super().__init__(application=application, title="LexOS Boost")
        self.set_default_size(760, 620)
        self.set_border_width(0)

        self.moteur = Moteur()
        self.niveau = self.moteur.niveau_conseille()
        self._processus: Gio.Subprocess | None = None

        self._construire()
        self._rafraichir_plan()

    # ------------------------------------------------------------ interface

    def _construire(self) -> None:
        entete = Gtk.HeaderBar(title="LexOS Boost", show_close_button=True)
        entete.set_subtitle(f"version {__version__}")
        self.set_titlebar(entete)

        self.bouton_etat = Gtk.Button(label="Ce qui est en place")
        self.bouton_etat.connect("clicked", self._sur_etat)
        entete.pack_start(self.bouton_etat)

        colonne = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.add(colonne)

        # --- portrait de la machine ---------------------------------------
        cadre_machine = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        cadre_machine.set_border_width(16)

        profil = self.moteur.calculer_profil(self.niveau)
        titre = Gtk.Label(xalign=0)
        titre.set_markup(
            f"<span size='large' weight='bold'>Ta machine est "
            f"{GLib.markup_escape_text(profil.classe_lisible())}</span>"
        )
        cadre_machine.pack_start(titre, False, False, 0)

        detail = Gtk.Label(label=self.moteur.machine.resume(), xalign=0)
        detail.set_line_wrap(True)
        detail.get_style_context().add_class("dim-label")
        cadre_machine.pack_start(detail, False, False, 0)
        colonne.pack_start(cadre_machine, False, False, 0)

        colonne.pack_start(Gtk.Separator(), False, False, 0)

        # --- choix du niveau ----------------------------------------------
        boite_niveaux = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8, homogeneous=True)
        boite_niveaux.set_border_width(16)

        self.boutons_niveau: dict[str, Gtk.RadioButton] = {}
        precedent = None
        for identifiant in NIVEAUX:
            nom, description = DESCRIPTIONS[identifiant]
            bouton = Gtk.RadioButton.new_with_label_from_widget(precedent, nom)
            precedent = precedent or bouton
            bouton.set_tooltip_text(description)
            bouton.connect("toggled", self._sur_niveau, identifiant)
            if identifiant == self.niveau:
                bouton.set_active(True)
            self.boutons_niveau[identifiant] = bouton

            case = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            case.pack_start(bouton, False, False, 0)
            explication = Gtk.Label(label=description, xalign=0)
            explication.set_line_wrap(True)
            explication.set_max_width_chars(28)
            explication.get_style_context().add_class("dim-label")
            case.pack_start(explication, False, False, 0)
            boite_niveaux.pack_start(case, True, True, 0)

        colonne.pack_start(boite_niveaux, False, False, 0)

        conseil = Gtk.Label(xalign=0)
        conseil.set_markup(
            f"<i>Conseillé pour cette machine : "
            f"{DESCRIPTIONS[self.moteur.niveau_conseille()][0]}</i>"
        )
        conseil.set_margin_start(16)
        conseil.set_margin_bottom(8)
        colonne.pack_start(conseil, False, False, 0)

        colonne.pack_start(Gtk.Separator(), False, False, 0)

        # --- ce qui va être fait ------------------------------------------
        defilement = Gtk.ScrolledWindow()
        defilement.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.liste = Gtk.ListBox()
        self.liste.set_selection_mode(Gtk.SelectionMode.NONE)
        defilement.add(self.liste)
        colonne.pack_start(defilement, True, True, 0)

        # --- sortie en direct ---------------------------------------------
        self.defilement_sortie = Gtk.ScrolledWindow()
        self.defilement_sortie.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        self.defilement_sortie.set_size_request(-1, 180)
        self.sortie = Gtk.TextView(editable=False, cursor_visible=False)
        self.sortie.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        self.sortie.override_font(Pango.FontDescription("monospace 9"))
        self.defilement_sortie.add(self.sortie)
        colonne.pack_start(self.defilement_sortie, False, False, 0)
        self.defilement_sortie.set_no_show_all(True)

        # --- barre d'actions ----------------------------------------------
        barre = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        barre.set_border_width(12)

        self.bouton_annuler = Gtk.Button(label="Tout remettre comme avant")
        self.bouton_annuler.connect("clicked", self._sur_annuler)
        barre.pack_start(self.bouton_annuler, False, False, 0)

        self.bouton_simulation = Gtk.Button(label="Voir sans rien changer")
        self.bouton_simulation.connect("clicked", self._sur_simulation)
        barre.pack_end(self.bouton_simulation, False, False, 0)

        self.bouton_appliquer = Gtk.Button(label="Optimiser ma machine")
        self.bouton_appliquer.get_style_context().add_class("suggested-action")
        self.bouton_appliquer.connect("clicked", self._sur_appliquer)
        barre.pack_end(self.bouton_appliquer, False, False, 0)

        colonne.pack_start(barre, False, False, 0)

    # -------------------------------------------------------------- contenu

    def _ligne(self, marque: str, titre: str, detail: str, attenue: bool) -> Gtk.ListBoxRow:
        ligne = Gtk.ListBoxRow(activatable=False)
        boite = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        boite.set_border_width(8)

        symbole = Gtk.Label(label=marque)
        symbole.set_valign(Gtk.Align.START)
        symbole.set_size_request(18, -1)
        boite.pack_start(symbole, False, False, 0)

        texte = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        etiquette = Gtk.Label(label=titre, xalign=0)
        if attenue:
            etiquette.get_style_context().add_class("dim-label")
        texte.pack_start(etiquette, False, False, 0)
        if detail:
            sous_titre = Gtk.Label(label=detail, xalign=0)
            sous_titre.set_line_wrap(True)
            sous_titre.get_style_context().add_class("dim-label")
            texte.pack_start(sous_titre, False, False, 0)
        boite.pack_start(texte, True, True, 0)

        ligne.add(boite)
        return ligne

    def _rafraichir_plan(self) -> None:
        for enfant in self.liste.get_children():
            self.liste.remove(enfant)

        profil = self.moteur.calculer_profil(self.niveau)
        entete = self._ligne(
            "→",
            f"Gain attendu : {profil.gain_attendu}",
            " · ".join(profil.notes[:3]),
            False,
        )
        self.liste.add(entete)

        retenues = 0
        for etape in self.moteur.plan(self.niveau):
            if etape.deja_appliquee:
                self.liste.add(self._ligne("≡", etape.action.titre, "déjà appliquée", True))
            elif etape.retenue:
                retenues += 1
                self.liste.add(self._ligne(
                    "✚", etape.action.titre,
                    etape.gain or etape.action.explication, False,
                ))
            else:
                self.liste.add(self._ligne("–", etape.action.titre, etape.raison, True))

        self.bouton_appliquer.set_sensitive(retenues > 0)
        self.bouton_appliquer.set_label(
            "Optimiser ma machine" if retenues else "Rien à optimiser"
        )
        self.liste.show_all()

    # -------------------------------------------------------------- actions

    def _sur_niveau(self, bouton: Gtk.RadioButton, identifiant: str) -> None:
        if bouton.get_active():
            self.niveau = identifiant
            self._rafraichir_plan()

    def _sur_etat(self, _bouton: Gtk.Button) -> None:
        lignes = self.moteur.etat()
        if lignes:
            corps = "\n".join(f"• {titre}  ({quand})" for titre, quand, _ in lignes)
            texte = f"{len(lignes)} modification(s) en place :\n\n{corps}"
        else:
            texte = "LexOS Boost n'a rien changé sur cette machine."
        boite = Gtk.MessageDialog(
            transient_for=self, modal=True,
            message_type=Gtk.MessageType.INFO, buttons=Gtk.ButtonsType.CLOSE,
            text="Ce qui est en place",
        )
        boite.format_secondary_text(texte)
        boite.run()
        boite.destroy()

    def _sur_simulation(self, _bouton: Gtk.Button) -> None:
        self._lancer(["--appliquer", self.niveau, "--simulation"], privilegie=True)

    def _sur_appliquer(self, _bouton: Gtk.Button) -> None:
        self._lancer(["--appliquer", self.niveau], privilegie=True)

    def _sur_annuler(self, _bouton: Gtk.Button) -> None:
        boite = Gtk.MessageDialog(
            transient_for=self, modal=True,
            message_type=Gtk.MessageType.QUESTION, buttons=Gtk.ButtonsType.OK_CANCEL,
            text="Tout remettre comme avant ?",
        )
        boite.format_secondary_text(
            "Chaque réglage appliqué par LexOS Boost sera défait, dans l'ordre "
            "inverse de son application. Rien d'autre ne sera touché."
        )
        reponse = boite.run()
        boite.destroy()
        if reponse == Gtk.ResponseType.OK:
            self._lancer(["--annuler"], privilegie=True)

    # ------------------------------------------------------------ exécution

    def _verrouiller(self, verrouille: bool) -> None:
        for bouton in (
            self.bouton_appliquer, self.bouton_simulation,
            self.bouton_annuler, self.bouton_etat,
        ):
            bouton.set_sensitive(not verrouille)
        for bouton in self.boutons_niveau.values():
            bouton.set_sensitive(not verrouille)

    def _ecrire(self, texte: str) -> None:
        tampon = self.sortie.get_buffer()
        tampon.insert(tampon.get_end_iter(), texte)
        self.sortie.scroll_to_iter(tampon.get_end_iter(), 0.0, False, 0.0, 0.0)

    def _lancer(self, arguments: list[str], privilegie: bool) -> None:
        if self._processus is not None:
            return

        commande = ["/usr/bin/lexos-boost", "--sans-couleur"] + arguments
        if privilegie:
            commande = ["pkexec"] + commande

        self.sortie.get_buffer().set_text("")
        self.defilement_sortie.set_no_show_all(False)
        self.defilement_sortie.show_all()
        self._verrouiller(True)

        try:
            self._processus = Gio.Subprocess.new(
                commande,
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_MERGE,
            )
        except GLib.Error as erreur:
            self._ecrire(f"Impossible de lancer l'opération : {erreur.message}\n")
            self._verrouiller(False)
            self._processus = None
            return

        flux = Gio.DataInputStream.new(self._processus.get_stdout_pipe())
        self._lire_suite(flux)
        self._processus.wait_async(None, self._sur_fin)

    def _lire_suite(self, flux: Gio.DataInputStream) -> None:
        flux.read_line_async(GLib.PRIORITY_DEFAULT, None, self._sur_ligne, flux)

    def _sur_ligne(self, flux: Gio.DataInputStream, resultat, _donnees) -> None:
        try:
            ligne, _ = flux.read_line_finish(resultat)
        except GLib.Error:
            return
        if ligne is None:
            return
        self._ecrire(ligne.decode("utf-8", "replace") + "\n")
        self._lire_suite(flux)

    def _sur_fin(self, processus: Gio.Subprocess, resultat) -> None:
        try:
            processus.wait_finish(resultat)
            code = processus.get_exit_status()
        except GLib.Error:
            code = -1

        self._processus = None
        self._verrouiller(False)

        if code == 126:
            self._ecrire("\nOpération annulée : mot de passe non fourni.\n")
        elif code not in (0, 126):
            self._ecrire(f"\nTerminé avec des avertissements (code {code}).\n")

        # le moteur relit le matériel et le journal
        self.moteur = Moteur()
        self._rafraichir_plan()


class Application(Gtk.Application):
    def __init__(self) -> None:
        super().__init__(application_id="org.lexos.Boost")

    def do_activate(self) -> None:
        fenetre = self.get_active_window() or Fenetre(self)
        fenetre.show_all()
        fenetre.present()


def main() -> int:
    return Application().run(sys.argv)


if __name__ == "__main__":
    raise SystemExit(main())
