"""Lire la machine SANS que le lent retienne les autres — écrit UNE fois.

═══ CE FICHIER EST UN DÉMÉNAGEMENT, PAS UNE ÉCRITURE ═══
_de_front() et _sans_lever() viennent de settings.py (l. ~4053 et ~4103) et
de volet.py, où ils existaient en DEUX exemplaires. Leurs commentaires
arrivent avec eux : chacun consigne un vrai bogue, trouvé sur la machine
d'Alex. Une réécriture les perdrait en silence, et les bogues reviendraient
un par un sur des mois sans qu'on fasse le lien.

Rien de ce que les collecteurs lisent ne change. Seul leur ORDONNANCEMENT
change : ils ne s'attendent plus les uns les autres.

═══ LA LOI DE CE MODULE ═══
None veut dire « je n'ai pas pu lire », JAMAIS « c'est vide ». Les deux ne
se ressemblent pas à l'écran — l'un veut dire « aucun réseau », l'autre « je
ne sais pas s'il y en a » — et les confondre est exactement ce qui faisait
dire au dock « c'est à droite » quand il n'en savait rien.
"""

from __future__ import annotations

import concurrent.futures
import time

#  Combien de collecteurs tournent en même temps. Douze, parce que ce sont
#  des attentes et non du calcul : le processeur ne fait rien pendant qu'un
#  nmcli répond.
FRONTS = 12


def sans_lever(f):
    """Un collecteur qui lève ne doit pas emporter les autres avec lui.

    ═══ DÉPLACÉ DE settings.py, À L'IDENTIQUE ═══
    Ils sont écrits pour ne jamais lever ; ce filet existe parce que « écrit
    pour » n'est pas « garanti », et qu'une exception dans un fil du pool
    remonterait ici sous une forme méconnaissable."""
    try:
        return f()
    except Exception:
        return None


def de_front(collecteurs, delai, fronts: int = FRONTS, replis=None):
    """Lance les collecteurs EN MÊME TEMPS et rend {clé: valeur}.

    « collecteurs » : {clé: appelable sans argument}. C'est ce qui permet de
    les lancer ensemble.
    « replis » : {clé: valeur} pour ceux qui n'aboutissent pas. Absent, la
    valeur est None — « je ne sais pas ». Le volet, lui, choisit la sienne
    pour chaque clé : un booléen manquant n'a pas la même tête qu'une liste
    manquante.

    ═══ CELUI QUI TRAÎNE NE RETIENT PLUS PERSONNE ═══
    Une imprimante réseau éteinte, bluetoothctl sans adaptateur, nmcli
    pendant un balayage : il suffisait d'UN outil lent pour que les
    trente-sept autres sections attendent avec lui. Passé le délai, la clé
    vaut son repli — et la page le dit. On n'invente pas de valeur : c'est la
    leçon du bogue du dock, où « je ne sais pas » était devenu « c'est à
    droite ».

    ═══ PAS DE « with » ICI, ET C'EST TOUT LE POINT ═══
    La sortie d'un « with ThreadPoolExecutor » appelle shutdown(wait=True) :
    elle ATTEND tous les fils, y compris ceux qu'on vient d'abandonner. Le
    délai ne tenait donc pas — MESURÉ : avec tous les outils muets, etat()
    rendait la main au bout de 63 s au lieu des 4 s annoncées, parce que la
    fermeture du pool rattrapait tout ce que la boucle avait lâché. On ferme
    donc à la main, sans attendre.

    Le fil qui traîne n'est PAS tué : on ne peut pas interrompre proprement
    un appel système en cours, et l'essayer laisserait un sous-processus
    orphelin. On cesse simplement de l'attendre ; il finira dans son coin, et
    son propre timeout (deux secondes de lecture) le bornera."""
    if not collecteurs:
        return {}
    replis = replis or {}
    resultats = {}
    fin = time.monotonic() + delai
    pool = concurrent.futures.ThreadPoolExecutor(
        max_workers=min(fronts, len(collecteurs)),
        thread_name_prefix="lexos-etat")
    try:
        futurs = {pool.submit(sans_lever, f): k for k, f in collecteurs.items()}
        for fut, cle in futurs.items():
            reste = max(0.0, fin - time.monotonic())
            try:
                resultats[cle] = fut.result(timeout=reste)
            except concurrent.futures.TimeoutError:
                resultats[cle] = replis.get(cle)
            except Exception:
                resultats[cle] = replis.get(cle)
    finally:
        pool.shutdown(wait=False)
    return resultats
