#!/usr/bin/env python3
"""lexos-ia-agent — boucle d'agent autonome pour lexos-ia.

Appelé par lexos-ia (bash), jamais directement par l'utilisateur.
Parle à Ollama en local (aucune donnée n'est envoyée sur internet), propose
une commande, l'exécute, regarde le résultat, recommence — jusqu'à ce que
la tâche soit finie ou qu'on atteigne la limite d'étapes.

Règle de la maison, comme lexos-format : jamais de commande destructrice
sans confirmation explicite, et jamais sudo par défaut.
"""
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

MAX_STEPS = 20
TIMEOUT_S = 30
MAX_OUTPUT = 4000

BLOCKLIST = [
    r"\brm\s+(-\w*r\w*f\w*|-\w*f\w*r\w*)\s+/(\s|$)",
    r"\brm\s+(-\w*r\w*f\w*|-\w*f\w*r\w*)\s+~(\s|$|/\s*$)",
    r"\bmkfs(\.\w+)?\b",
    r"\bdd\b[^\n]*\bof=/dev/",
    r"\bwipefs\b",
    r"\bparted\b",
    r"\bfdisk\b",
    r"\bgdisk\b",
    r">\s*/dev/sd[a-z]",
    r">\s*/dev/nvme\d",
    r":\(\)\s*\{\s*:\s*\|\s*:\s*;\s*\}\s*;\s*:",
    r"\bshutdown\b",
    r"\breboot\b",
    r"\bpoweroff\b",
    r"\bhalt\b",
    r"\buserdel\b",
    r"\bpasswd\b",
    r"\bvisudo\b",
    r"\bcurl\b[^\n]*\|\s*(sh|bash)\b",
    r"\bwget\b[^\n]*\|\s*(sh|bash)\b",
]
BLOCKLIST_RE = [re.compile(p, re.IGNORECASE) for p in BLOCKLIST]

# -----------------------------------------------------------------------------
#  Liste BLANCHE — le vrai garde-fou.
# -----------------------------------------------------------------------------
#  Une liste noire ne protège rien : « rm -rf /home », « rm -rf /* », « find /
#  -delete » ou « echo <base64> | base64 -d | sh » la contournent tous sans
#  effort, et on ne peut pas énumérer à l'avance toutes les façons d'abîmer une
#  machine. On inverse donc la logique : seules les commandes de LECTURE
#  connues tournent sans rien demander. Tout le reste passe par une
#  confirmation humaine, même en mode --auto.
READONLY_COMMANDS = {
    "ls", "cat", "head", "tail", "wc", "grep", "egrep", "fgrep", "find",
    "stat", "file", "du", "df", "pwd", "whoami", "id", "uname", "hostname",
    "date", "uptime", "free", "ps", "top", "lsblk", "lscpu", "lsusb", "lspci",
    "lsmod", "mount", "env", "printenv", "echo", "printf", "sort", "uniq",
    "cut", "awk", "sed", "tr", "column", "less", "more", "readlink", "dirname",
    "basename", "realpath", "which", "type", "command", "apt-cache", "dpkg-query",
    "systemctl", "journalctl", "ip", "nmcli", "ping", "dig", "host", "sha256sum",
    "md5sum", "locale", "lexfetch", "true", "false", "test",
}
# Sous-commandes qui écrivent, pour des binaires par ailleurs inoffensifs.
WRITING_SUBCOMMANDS = {
    "systemctl": {"start", "stop", "restart", "reload", "enable", "disable",
                  "mask", "unmask", "isolate", "kill", "set-property"},
    "ip": {"add", "del", "delete", "set", "flush", "change", "replace"},
    "nmcli": {"add", "delete", "modify", "edit", "up", "down", "import"},
}
SPLIT_RE = re.compile(r"\|\||&&|[;|\n]")
REDIRECT_RE = re.compile(r"(?<![0-9<>])>{1,2}(?!&)|(?<![0-9<>])>\|")
SUBSHELL_RE = re.compile(r"\$\(|`|<\(")


def blocked_reason(cmd):
    """Refus dur — deuxième filet, jamais le seul."""
    for rx in BLOCKLIST_RE:
        if rx.search(cmd):
            return "commande jugée destructrice ou dangereuse, refusée par mesure de sécurité"
    return None


def needs_confirmation(cmd):
    """Renvoie None si la commande est une lecture sûre, sinon la raison du doute.

    Tout ce qui n'est pas explicitement reconnu comme lecture seule exige une
    confirmation humaine — y compris en mode --auto.
    """
    if SUBSHELL_RE.search(cmd):
        return "contient une substitution de commande"
    if REDIRECT_RE.search(cmd):
        return "écrit dans un fichier (redirection)"
    for segment in SPLIT_RE.split(cmd):
        parts = segment.split()
        if not parts:
            continue
        # Ignore les VAR=valeur en tête de commande.
        while parts and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", parts[0]):
            parts = parts[1:]
        if not parts:
            continue
        prog = os.path.basename(parts[0])
        if prog not in READONLY_COMMANDS:
            return f"« {prog} » n'est pas une commande de lecture connue"
        writing = WRITING_SUBCOMMANDS.get(prog)
        if writing and any(a in writing for a in parts[1:]):
            return f"« {prog} » est utilisé pour modifier quelque chose"
        if prog == "find" and re.search(r"-(delete|exec|execdir|ok|okdir|fls|fprint)\b", segment):
            return "« find » est utilisé pour agir sur les fichiers, pas seulement les lister"
    return None


def say(msg):
    print(f"\033[38;5;208m»\033[0m {msg}")


def ok(msg):
    print(f"\033[32m✓\033[0m {msg}")


def err(msg):
    print(f"\033[31m✗\033[0m {msg}", file=sys.stderr)


SYSTEM_PROMPT = (
    "Tu es l'agent IA de LexOS, un assistant qui accomplit des tâches sur "
    "une vraie machine Linux (Debian) en exécutant des commandes shell, "
    "une à la fois, jusqu'à avoir répondu à la tâche demandée. "
    "Réponds TOUJOURS en JSON valide, rien d'autre, sous une de ces deux formes : "
    '{"action": "run", "commande": "<commande shell>", "raison": "<courte raison>"} '
    "quand tu as besoin d'exécuter une commande pour avancer, ou "
    '{"action": "fini", "reponse": "<réponse finale en français>"} '
    "quand tu as terminé et peux répondre à l'utilisateur. "
    "Une seule commande à la fois. Pas de sudo (désactivé par défaut). "
    "Pas de commande qui efface, formate ou écrase un disque. "
    "Si une commande est refusée, propose une autre approche non destructrice."
)


def ollama_chat(host, model, messages):
    body = json.dumps({
        "model": model,
        "messages": messages,
        "format": "json",
        "stream": False,
    }).encode("utf-8")
    req = urllib.request.Request(
        f"http://{host}/api/chat", data=body,
        headers={"Content-Type": "application/json"}, method="POST",
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.loads(resp.read().decode("utf-8"))


def run_command(cmd):
    try:
        proc = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=TIMEOUT_S,
        )
        out = (proc.stdout or "") + (proc.stderr or "")
        out = out[:MAX_OUTPUT]
        return proc.returncode, out
    except subprocess.TimeoutExpired:
        return None, f"(dépassement du délai de {TIMEOUT_S}s — commande interrompue)"


def main():
    host = os.environ.get("LEXOS_IA_HOST", "127.0.0.1:11434")
    model = os.environ.get("LEXOS_IA_MODEL", "qwen2.5:3b")
    task = os.environ.get("LEXOS_IA_TASK", "").strip()
    auto = os.environ.get("LEXOS_IA_AUTO", "0") == "1"
    allow_sudo = os.environ.get("LEXOS_IA_SUDO", "0") == "1"

    if not task:
        err("Aucune tâche fournie.")
        return 1

    say(f"Tâche : {task}")
    if not auto:
        say("Chaque commande te sera montrée avant d'être exécutée (Entrée = "
            "continuer, n = refuser). Mode --auto pour sauter cette étape.")

    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": task},
    ]

    for step in range(1, MAX_STEPS + 1):
        try:
            resp = ollama_chat(host, model, messages)
        except urllib.error.URLError:
            err("Impossible de joindre Ollama sur " + host + " — lance : lexos ia setup")
            return 1
        except (TimeoutError, OSError) as exc:
            err(f"Erreur de communication avec Ollama : {exc}")
            return 1

        content = resp.get("message", {}).get("content", "")
        try:
            parsed = json.loads(content)
        except json.JSONDecodeError:
            err(f"Réponse du modèle illisible (étape {step}), arrêt.")
            return 1

        action = parsed.get("action")

        if action == "fini":
            ok(parsed.get("reponse", "Terminé."))
            return 0

        if action != "run":
            err("Réponse inattendue du modèle, arrêt.")
            return 1

        cmd = (parsed.get("commande") or "").strip()
        raison = parsed.get("raison", "")
        if not cmd:
            messages.append({"role": "assistant", "content": content})
            messages.append({"role": "user", "content": "Commande vide, réessaie."})
            continue

        reason_blocked = blocked_reason(cmd)
        if not reason_blocked and not allow_sudo and re.search(r"\bsudo\b", cmd):
            reason_blocked = "sudo est désactivé par défaut (relance avec --sudo pour l'autoriser)"

        if reason_blocked:
            err(f"Commande refusée : {cmd}  ({reason_blocked})")
            messages.append({"role": "assistant", "content": content})
            messages.append({"role": "user",
                              "content": f"Commande refusée ({reason_blocked}). Propose autre chose."})
            continue

        print(f"\033[2m[{step}/{MAX_STEPS}]\033[0m {raison}")
        print(f"  $ {cmd}")

        # --auto ne lève la confirmation que pour les commandes de LECTURE
        # reconnues. Tout ce qui pourrait modifier la machine reste soumis à
        # un accord humain explicite, quelles que soient les options.
        doubt = needs_confirmation(cmd)
        if not auto or doubt:
            if doubt:
                print(f"  \033[33m!\033[0m Cette commande peut modifier ta machine — {doubt}.")
            if not sys.stdin.isatty():
                err("Confirmation impossible (pas de terminal) — commande non exécutée.")
                messages.append({"role": "assistant", "content": content})
                messages.append({"role": "user",
                                  "content": "Commande non exécutée : elle exige une confirmation "
                                             "humaine, impossible ici. Propose une commande de lecture seule."})
                continue
            try:
                reply = input("  Exécuter ? [o = oui / Entrée = non] ").strip().lower()
            except EOFError:
                reply = ""
            if reply not in ("o", "oui", "y", "yes"):
                messages.append({"role": "assistant", "content": content})
                messages.append({"role": "user", "content": "Refusé par l'utilisateur. Propose autre chose."})
                continue

        code, output = run_command(cmd)
        print(output.strip() or "(aucune sortie)")

        messages.append({"role": "assistant", "content": content})
        messages.append({
            "role": "user",
            "content": f"Résultat (code {code}) :\n{output}",
        })

    err(f"Limite de {MAX_STEPS} étapes atteinte sans conclusion — reformule la tâche.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
