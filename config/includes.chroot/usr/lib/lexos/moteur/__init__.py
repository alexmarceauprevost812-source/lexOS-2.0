"""Le socle commun des fenêtres LexOS — Paramètres, volet, et leurs voisins.

Ce que ce paquet tient à un seul endroit, au lieu de six :
    outils.py    les outils du système, demandés une fois (mémoire + délais)

À venir, dans l'ordre des étapes :
    service.py   UNE classe Handler (/api/etat, /api/action)
    fenetre.py   UNE fabrique de fenêtre Qt
    registre.py  déclarer un collecteur et une action
    etat.py      les collecteurs menés de front, le cache et son invalidation
    web/client.js  UN client : api(), chargeEtat(cles), l'affichage optimiste

⚠ boost/moteur.py porte le même mot et fait autre chose : lui applique les
profils de performance. Les deux se renvoient l'un à l'autre en tête de
fichier, parce que le lecteur de l'un tombera forcément sur l'autre un jour.

LA RÈGLE DE CE PAQUET, ET ELLE PRIME SUR TOUT : on DÉPLACE, on ne réécrit
pas. Les commentaires de settings.py ne sont pas de la décoration — chacun
consigne un vrai bogue, souvent trouvé après une gravure d'ISO et un
redémarrage. Une réécriture les perdrait en silence, et les bogues
reviendraient un par un sur des mois sans qu'on fasse le lien.
"""
