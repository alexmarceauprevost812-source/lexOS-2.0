#!/usr/bin/env bash
# =============================================================================
#  Éprouver la Logithèque — les icônes ne doivent plus être des carrés noirs
# =============================================================================
#  ALEX, TROIS PHOTOS DE LA LOGITHÈQUE : « les couleurs, le noir en carré —
#  je veux pas voir le noir en carré, ça fait pas très joli, dans
#  logithèque ». Sur ses captures, la moitié des applications proposées
#  (ImageFan Reloaded, Boxy SVG, Deezer, Lotti, Blackbody, EdiTidE, Gameeky)
#  montrent un carré sombre à la place de leur icône, pendant que d'autres
#  (Zen, Bouteilles, HashVerifier, Kisel, Girens) s'affichent normalement.
#
#  ═══ LA CAUSE, VÉRIFIÉE PLUTÔT QUE DEVINÉE ═══
#  « flatpak remote-add » ne fait qu'ENREGISTRER le dépôt. C'est tout ce que
#  son aide annonce, mot pour mot : « Add a new remote repository (by URL) ».
#  Les métadonnées AppStream — qui portent le nom, le résumé ET LES ICÔNES de
#  chaque application — sont téléchargées par une AUTRE commande, dont l'aide
#  dit exactement ce qu'elle fait : « flatpak update --appstream » →
#  « Update appstream for remote ». Cette commande n'était appelée nulle part
#  dans LexOS. GNOME Logiciels affichait donc ce qu'il avait pu glaner (des
#  noms, des résumés) et un carré vide partout où l'icône manquait.
#
#  ═══ POURQUOI ÇA NE DEMANDERA PAS DE MOT DE PASSE ═══
#  Lu dans la politique polkit livrée PAR FLATPAK LUI-MÊME
#  (/usr/share/polkit-1/actions/org.freedesktop.Flatpak.policy) : l'action
#  « org.freedesktop.Flatpak.appstream-update » porte
#  « <allow_active>yes</allow_active> » — une session locale active y a droit
#  SANS authentification. C'est ce qui permet de la lancer à chaque ouverture
#  sans transformer la boutique en interrogatoire, et c'est pour ça que le
#  banc vérifie plus bas qu'elle N'EST PAS enveloppée dans sudo_cmd.
#
#  ═══ CE QUE CE BANC NE PEUT PAS FAIRE ═══
#  Joindre Flathub. La machine de construction n'a pas accès à
#  dl.flathub.org (essayé : « Failure when receiving data from the peer »),
#  et il n'y a ni serveur X ni GNOME Logiciels ici pour REGARDER une icône.
#  Le banc éprouve donc ce qui est éprouvable sans réseau ni écran : quelles
#  commandes le script lance VRAIMENT, dans quel ordre, avec quels droits, et
#  sans bloquer l'ouverture de la boutique. Que les icônes apparaissent
#  ensuite à l'écran, seul Alex peut le confirmer.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$RACINE/config/includes.chroot/usr/bin/lexos-logitheque"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[ -r "$SCRIPT" ] || { non "lexos-logitheque introuvable"; echo; exit 1; }

# =============================================================================
#  Un PATH FERMÉ, et de faux outils qui NOTENT au lieu d'agir.
# =============================================================================
#  Aucun vrai flatpak, aucun vrai gnome-software : on regarde ce que le
#  script DEMANDE. « gnome-software » sort en 0 tout de suite — le script
#  finit par « exec gnome-software », donc c'est lui qui termine le
#  processus, et sans ce faux-là le banc lancerait une vraie boutique.
#  UN PATH VRAIMENT FERMÉ, ET C'EST LE BANC QUI S'EN EST ACCUSÉ.
#  Première version : PATH="$BANC/bin:/usr/bin:/bin". Le cas « sans flatpak »
#  effaçait le faux flatpak… et le script trouvait le VRAI dans /usr/bin —
#  il est installé sur cette machine de construction. Le contrôle passait
#  donc à côté, et pire : le vrai flatpak est parti appeler dl.flathub.org
#  pour de bon. Un PATH qui laisse filtrer le système ne prouve pas une
#  absence. On construit donc un /bin à nous, avec exactement les outils que
#  le script emploie, et rien d'autre.
OUTILS_REELS="grep sed cat head awk tr sleep"
sysbin() {
	rm -rf "${BANC:?}/sysbin"; mkdir -p "$BANC/sysbin"
	local o chemin
	for o in $OUTILS_REELS; do
		chemin="$(command -v "$o" 2>/dev/null)" || continue
		ln -sf "$chemin" "$BANC/sysbin/$o"
	done
}

prepare() { # prepare <flathub-deja-la: oui|non>
	rm -rf "${BANC:?}/bin" "$BANC/journal"
	mkdir -p "$BANC/bin"
	: > "$BANC/journal"
	sysbin

	cat > "$BANC/bin/flatpak" <<EOF
#!/bin/sh
echo "flatpak \$*" >> "$BANC/journal"
case "\$*" in
  remotes) [ "$1" = "oui" ] && echo "flathub" ;;
esac
exit 0
EOF
	cat > "$BANC/bin/gnome-software" <<EOF
#!/bin/sh
echo "gnome-software \$*" >> "$BANC/journal"
exit 0
EOF
	#  sudo NOTE ce qu'on lui demande d'élever : c'est ainsi qu'on voit si
	#  une commande passe par les droits d'administration ou non.
	cat > "$BANC/bin/sudo" <<EOF
#!/bin/sh
echo "SUDO \$*" >> "$BANC/journal"
shift 0
exec "\$@"
EOF
	cat > "$BANC/bin/setsid" <<EOF
#!/bin/sh
echo "SETSID \$*" >> "$BANC/journal"
shift 0
exec "\$@"
EOF
	chmod +x "$BANC"/bin/*
}

lance() {
	#  « id -u » vaut 0 dans ce conteneur : sudo_cmd exécuterait alors
	#  directement, sans passer par notre faux sudo, et on ne verrait pas
	#  la différence entre « élevé » et « pas élevé ». On force donc le
	#  script à croire qu'il n'est pas root en lui donnant un faux « id ».
	cat > "$BANC/bin/id" <<'EOF'
#!/bin/sh
[ "$1" = "-u" ] && { echo 1000; exit 0; }
exit 0
EOF
	chmod +x "$BANC/bin/id"
	#  « timeout », « env » ET « bash » sont résolus AVANT que le PATH se
	#  referme — sinon c'est le banc lui-même qui ne trouve plus ses outils.
	#  Deux fois de suite sur ce piège : d'abord « timeout: command not
	#  found », puis « env: 'bash': No such file or directory » — env
	#  cherche le programme à lancer dans le PATH NEUF, pas dans l'ancien.
	#  Chaque fois, un journal vide qui faisait passer six contrôles pour
	#  des échecs du script alors que le script n'avait jamais démarré.
	timeout 20 env PATH="$BANC/bin:$BANC/sysbin" NO_COLOR=1 \
		"$BASH" "$SCRIPT" >/dev/null 2>&1
	#  Les tâches de fond du script écrivent dans le journal APRÈS que le
	#  script a rendu la main : on leur laisse un instant.
	sleep 1
	cat "$BANC/journal" 2>/dev/null
}

# =============================================================================
titre "1. Les métadonnées AppStream sont VRAIMENT demandées (les icônes)"
# =============================================================================
prepare oui
J="$(lance)"

grep -q -- "flatpak update --appstream" <<< "$J" \
	&& ok "« flatpak update --appstream » est lancée — c'est elle qui apporte les icônes" \
	|| non "aucun « update --appstream » : les icônes resteraient des carrés vides — le bogue d'Alex : $J"

grep -q "gnome-software" <<< "$J" \
	&& ok "et la boutique s'ouvre quand même" \
	|| non "la boutique ne s'ouvre plus : $J"

# =============================================================================
titre "2. Sans mot de passe, et sans faire attendre devant un écran figé"
# =============================================================================
#  LE POINT QUI COMPTE : la mise à jour AppStream ne doit PAS passer par
#  sudo. polkit l'autorise déjà pour une session active (allow_active=yes,
#  voir l'en-tête) ; l'envelopper dans sudo redemanderait un mot de passe à
#  CHAQUE ouverture de la Logithèque.
#  ═══ CES DEUX CONTRÔLES SE LISENT SUR LE TEXTE DU SCRIPT, ET IL LE FAUT ═══
#  Première version : ils regardaient le JOURNAL des faux outils. Les deux
#  mutations correspondantes sont passées à travers, et pour deux raisons
#  différentes qu'il vaut mieux écrire que réapprendre :
#    · « sudo_cmd » est une FONCTION shell. « setsid sudo_cmd … » échoue donc
#      sans rien exécuter : aucune ligne SUDO au journal, et le banc concluait
#      « pas de sudo » sur une commande qui ne tournait pas du tout.
#    · le « & » manquant sur UNE des deux branches (setsid / repli) laissait
#      l'autre branche satisfaire un grep global. « Au moins une est en tâche
#      de fond » ne dit rien : c'est CHAQUE appel qui doit l'être.
#  On énumère donc TOUTES les lignes qui lancent --appstream, et chacune doit
#  passer les deux exigences. Zéro ligne est un échec, pas un succès.
LIGNES_AS="$(grep -nE '^[^#]*flatpak update --appstream' "$SCRIPT" || true)"
NB_AS="$(printf '%s' "$LIGNES_AS" | grep -c . || true)"

if [ "$NB_AS" -eq 0 ]; then
	non "aucune ligne ne lance « flatpak update --appstream » dans le script"
else
	MAUVAIS=0
	while IFS= read -r l; do
		[ -n "$l" ] || continue
		case "$l" in *sudo*|*pkexec*) MAUVAIS=$((MAUVAIS + 1)) ;; esac
	done <<< "$LIGNES_AS"
	[ "$MAUVAIS" -eq 0 ] \
		&& ok "aucun des $NB_AS appels AppStream ne passe par sudo (polkit l'autorise déjà)" \
		|| non "$MAUVAIS appel(s) AppStream passent par sudo — un mot de passe à chaque ouverture"

	#  ET AUCUN NE BLOQUE. Le premier téléchargement pèse des dizaines de
	#  mégaoctets : l'attendre ferait passer « j'ai cliqué » pour un plantage.
	#  Un banc ne peut pas chronométrer un réseau qu'il n'a pas — on lit donc
	#  le « & » de fin de ligne, sur CHAQUE appel.
	BLOQUANTS=0
	while IFS= read -r l; do
		[ -n "$l" ] || continue
		case "$l" in *'&') ;; *) BLOQUANTS=$((BLOQUANTS + 1)) ;; esac
	done <<< "$LIGNES_AS"
	[ "$BLOQUANTS" -eq 0 ] \
		&& ok "les $NB_AS appels AppStream sont en tâche de fond (la boutique s'ouvre tout de suite)" \
		|| non "$BLOQUANTS appel(s) AppStream bloquent — la boutique aurait l'air plantée"
fi

grep -q "setsid" "$SCRIPT" \
	&& ok "setsid la détache vraiment (elle survit à « exec gnome-software »)" \
	|| non "sans setsid, le téléchargement dépend de la façon dont le terminal range ses enfants"

# =============================================================================
titre "3. Le dépôt Flathub : ajouté s'il manque, pas ré-ajouté s'il est là"
# =============================================================================
prepare non
J="$(lance)"
grep -q "remote-add" <<< "$J" \
	&& ok "Flathub absent -> il est ajouté" \
	|| non "Flathub manquant et jamais ajouté : $J"
#  Celui-là, en revanche, DOIT être élevé : modifier les dépôts du système
#  est « configure-remote » côté polkit, avec auth_admin.
grep "SUDO" <<< "$J" | grep -q "remote-add" \
	&& ok "…et l'ajout du dépôt, lui, passe bien par les droits d'administration" \
	|| non "l'ajout du dépôt ne passe pas par sudo : $J"

prepare oui
J="$(lance)"
grep -q "remote-add" <<< "$J" \
	&& non "Flathub déjà présent et pourtant ré-ajouté : $J" \
	|| ok "Flathub déjà là -> aucun ré-ajout inutile"
#  Mais les métadonnées, elles, sont rafraîchies à chaque fois : c'est
#  incrémental, et c'est précisément ce qui manquait.
grep -q -- "--appstream" <<< "$J" \
	&& ok "les métadonnées sont quand même rafraîchies (incrémental, donc peu coûteux)" \
	|| non "aucun rafraîchissement quand le dépôt est déjà là — les icônes ne viendraient jamais"

# =============================================================================
titre "4. Sans Flatpak du tout, rien ne casse"
# =============================================================================
#  flatpak est dans la liste OPTIONNELLE (95-logitheque.list) : il peut
#  manquer. La boutique doit alors s'ouvrir sur les seuls dépôts Debian,
#  sans un message d'erreur pour une commande qu'on ne pouvait pas lancer.
prepare oui
rm -f "$BANC/bin/flatpak"
J="$(lance)"
grep -q "gnome-software" <<< "$J" \
	&& ok "sans flatpak, la boutique s'ouvre quand même (dépôts Debian)" \
	|| non "sans flatpak, la boutique ne s'ouvre plus : $J"
grep -q -- "--appstream" <<< "$J" \
	&& non "un « update --appstream » lancé sans flatpak installé : $J" \
	|| ok "…et aucune commande flatpak n'est tentée"

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
