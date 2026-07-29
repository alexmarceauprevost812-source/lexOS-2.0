#!/usr/bin/env python3
"""
Crée la fenêtre dans laquelle mpv dessinera le fond d'écran animé.

Pourquoi une fenêtre à nous plutôt que celle du bureau ?
------------------------------------------------------
La recette qui circule consiste à donner à mpv l'identifiant de la fenêtre
de xfdesktop. Ça marche… jusqu'à ce que xfdesktop se redessine — au
changement de fond, à la connexion d'un écran, au retour de veille — et
efface la vidéo sans prévenir. On crée donc notre propre fenêtre, et
xfdesktop ne sait même pas qu'elle existe.

Trois propriétés font tout le travail :

  · override_redirect  — le gestionnaire de fenêtres ne la décore pas, ne
    la place pas, ne la met pas dans la barre des tâches. Elle n'est pas
    « une fenêtre » de son point de vue.
  · _NET_WM_WINDOW_TYPE_DESKTOP — elle se déclare comme un fond d'écran.
    « Afficher le bureau » ne la minimise donc pas.
  · lower() — elle passe sous tout le reste. Une fenêtre plein écran qui
    resterait au-dessus serait un bug spectaculaire.

Le programme affiche l'identifiant de la fenêtre sur la sortie standard,
puis reste en vie : la fenêtre disparaîtrait avec lui.
"""
import sys

try:
    from Xlib import X, display, Xatom
except ImportError:
    print("python3-xlib manquant", file=sys.stderr)
    sys.exit(2)


def main() -> None:
    try:
        ecran_x = display.Display()
    except Exception as e:  # pas de serveur X, ou DISPLAY absent
        print(f"connexion X impossible : {e}", file=sys.stderr)
        sys.exit(3)

    ecran = ecran_x.screen()
    racine = ecran.root
    largeur = ecran.width_in_pixels
    hauteur = ecran.height_in_pixels

    fenetre = racine.create_window(
        0, 0, largeur, hauteur, 0,
        ecran.root_depth,
        X.InputOutput,
        X.CopyFromParent,
        background_pixel=ecran.black_pixel,
        override_redirect=True,
        event_mask=X.StructureNotifyMask,
    )

    fenetre.change_property(
        ecran_x.intern_atom("_NET_WM_WINDOW_TYPE"), Xatom.ATOM, 32,
        [ecran_x.intern_atom("_NET_WM_WINDOW_TYPE_DESKTOP")],
    )
    #  Sans nom, la fenêtre est invisible aux outils de diagnostic : « qu'est-ce
    #  que c'est que cette fenêtre plein écran ? » doit avoir une réponse.
    fenetre.set_wm_name("LexOS — fond d'écran animé")
    fenetre.set_wm_class("lexos-fond-video", "LexOS")

    fenetre.map()
    fenetre.configure(stack_mode=X.Below)
    ecran_x.sync()

    print(fenetre.id, flush=True)

    #  Rester en vie : la fenêtre appartient à cette connexion X et
    #  disparaîtrait avec elle. next_event() bloque sans consommer de
    #  processeur — une boucle avec sleep en mangerait pour rien.
    try:
        while True:
            ecran_x.next_event()
    except KeyboardInterrupt:
        pass
    finally:
        try:
            fenetre.destroy()
            ecran_x.sync()
        except Exception:
            pass


if __name__ == "__main__":
    main()
