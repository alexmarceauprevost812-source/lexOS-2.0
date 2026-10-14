# LexOS Remote — ISO de test (Android + Starlink)

## Fonctionnement prévu

LexOS tourne sur le PC (chez soi). Depuis le Samsung Galaxy S25 Ultra, avec
Starlink ou les données mobiles, un client VNC (par exemple AVNC) affiche
**le même écran XFCE**. Les actions, le terminal, GitHub et l'IA Ollama
s'exécutent sur le PC, pas sur le téléphone.

Le QR indique seulement l'adresse privée **vnc://100.x.y.z:5900**.
Il ne contient aucun mot de passe, jeton Tailscale ou autre secret.
Selon l'application qui scanne le QR, il faut parfois copier l'adresse
dans le client VNC manuellement : le QR ne suffit pas à créer la connexion.

## Configuration avant la première connexion

1. Installer LexOS Pro, utiliser un **compte personnel avec mot de passe**,
   et vérifier le fonctionnement de la session XFCE/X11. Ne pas exposer la
   session Live/démo (compte invité/autologin) à un accès distant.
2. Installer Tailscale **depuis sa documentation officielle** sur le PC.
   Se connecter à son tailnet personnel et vérifier `tailscale status` et
   `tailscale ip -4`. Ne pas partager son compte ni ses clés.
3. Installer Tailscale et un client VNC sur Android. Se connecter avec
   le **même tailnet autorisé**, vérifier les règles d'accès Tailscale.
4. Sur LexOS, double-cliquer **LexOS Remote** sur le bureau, choisir
   « Démarrer le partage sécurisé » ; le mot de passe VNC est demandé
   localement. Le service n'est **jamais lancé au démarrage**.
5. Choisir « Afficher le code QR », puis le scanner depuis le téléphone
   ou recopier `100.x.y.z:5900` dans le client VNC.
6. Pour terminer, choisir « Arrêter le partage ». Vérifier son état.

## Sécurité et limites

- `lexos-distant partager` refuse de commencer sans adresse IPv4
  Tailscale valide ; `x11vnc` écoute uniquement sur cette adresse.
- Ne jamais rediriger le port TCP 5900 sur la box Internet ou Starlink.
- VNC possède une authentification ancienne limitée à 8 octets de mot de
  passe ; la protection repose également sur les accès Tailscale.
- Le QR n'effectue aucune authentification et n'octroie aucun accès.
- L'ordinateur doit rester allumé, connecté, avec une session graphique
  accessible. L'affichage distant peut être indisponible sur l'écran de
  connexion ou avec des sessions Wayland.
- Le PC peut lancer Ollama localement ; ce chantier n'installe ni ne
  configure Ollama.
- L'ISO de test est un artefact temporaire GitHub Actions, **pas une
  publication officielle**. Aucun disque n'est modifié par la compilation
  CI ; ne pas graver ni installer avant une vérification manuelle.

## Commandes de diagnostic

```bash
lexos distant --help
lexos distant etat
tailscale status
tailscale ip -4
```

Le partage peut aussi se piloter depuis le menu de bureau LexOS Remote.
Cette première étape n'inclut pas encore une APK personnalisée : un client
VNC Android permet d'abord de valider l'écran, la souris, le clavier et la
connexion via Starlink.
