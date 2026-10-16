"""Stockage local, projets et extensions explicites. Aucun chargement de plugin Python."""
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from uuid import uuid4


def atomic_write(path, text):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".rea-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def read_json(path, default):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except FileNotFoundError:
        return default
    except (ValueError, UnicodeError) as exc:
        raise ValueError(f"JSON illisible : {path}. Le fichier est conservé.") from exc


class Projects:
    def __init__(self, data_dir=None):
        self.directory = Path(data_dir or Path(os.getenv("XDG_DATA_HOME", Path.home() / ".local/share")) / "rea-studio")
        self.file = self.directory / "projects.json"

    def list(self):
        value = read_json(self.file, [])
        if not isinstance(value, list) or any(
            not isinstance(p, dict) or not all(isinstance(p.get(k), str) for k in ("id", "name", "path"))
            for p in value
        ):
            raise ValueError("Registre de projets invalide ; fichier conservé.")
        return value

    def _change(self, change):
        self.directory.mkdir(parents=True, exist_ok=True)
        with (self.directory / ".projects.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            projects = self.list()
            result = change(projects)
            atomic_write(self.file, json.dumps(projects, ensure_ascii=False, indent=2) + "\n")
            return result

    def add(self, directory, name=None):
        directory = Path(directory).expanduser().resolve(strict=True)
        if not directory.is_dir():
            raise ValueError("Choisir un dossier existant.")
        title = (name or directory.name).strip()
        if not title:
            raise ValueError("Le projet doit avoir un nom.")
        def change(projects):
            for project in projects:
                if project["path"] == str(directory):
                    return project
            project = {"id": uuid4().hex, "name": title, "path": str(directory)}
            projects.append(project)
            return project
        return self._change(change)

    def create(self, parent, name):
        name = name.strip()
        if not name or name in (".", "..") or re.search(r'[/\\\x00-\x1f]', name):
            raise ValueError("Nom invalide : utiliser un nom sans séparateur de chemin.")
        # Lire d'abord le registre : un registre corrompu ne crée aucun dossier.
        self.list()
        directory = Path(parent).expanduser().resolve(strict=True) / name
        directory.mkdir()  # Ne réutilise et ne remplace jamais un dossier existant.
        return self.add(directory, name)

    def rename(self, identity, name):
        if not name.strip():
            raise ValueError("Le nom ne peut pas être vide.")
        def change(projects):
            for p in projects:
                if p["id"] == identity:
                    p["name"] = name.strip()
        self._change(change)

    def forget(self, identity):
        def change(projects):
            projects[:] = [p for p in projects if p["id"] != identity]
        self._change(change)


def note_path(project):
    root = Path(project["path"]).resolve(strict=True)
    path = root / ".rea-studio" / "notes.md"
    # Un lien symbolique ne doit pas diriger la sauvegarde hors du projet.
    if not path.resolve().is_relative_to(root):
        raise ValueError("Le chemin des notes sort du projet via un lien symbolique.")
    return path


DEFAULT_TOOLS = [
    {"name": "Fichiers du projet", "argv": ["xdg-open", "{project}"], "terminal": False},
    {"name": "Studio+ LexOS : ateliers", "argv": ["lexos-studio", "liste"], "terminal": True},
    {"name": "GIMP", "argv": ["gimp"], "terminal": False},
    {"name": "Inkscape", "argv": ["inkscape"], "terminal": False},
]


def validate_tools(tools):
    if not isinstance(tools, list):
        raise ValueError("Les outils doivent former une liste JSON.")
    names = set()
    for tool in tools:
        if not isinstance(tool, dict) or not isinstance(tool.get("name"), str) or not tool["name"].strip():
            raise ValueError("Chaque outil doit avoir un nom.")
        argv = tool.get("argv")
        if not isinstance(argv, list) or not argv or any(not isinstance(a, str) or not a or "\0" in a for a in argv):
            raise ValueError("argv doit être une liste d'arguments non vides.")
        if not isinstance(tool.get("terminal", False), bool):
            raise ValueError("terminal doit être un booléen.")
        if "{project}" in argv[0] or tool["name"] in names:
            raise ValueError("Nom d'outil dupliqué ou exécutable invalide.")
        names.add(tool["name"])
    return tools


def tool_command(tool, project):
    validate_tools([tool])
    root = Path(project["path"]).resolve(strict=True)
    if not root.is_dir():
        raise ValueError("Le dossier du projet est absent.")
    argv = [a.replace("{project}", str(root)) for a in tool["argv"]]
    executable = shutil.which(argv[0])
    if not executable:
        raise ValueError(f"Outil absent : {argv[0]}. Installez-le séparément.")
    argv[0] = executable
    if tool.get("terminal", False):
        terminal = shutil.which("xfce4-terminal")
        if not terminal:
            raise ValueError("xfce4-terminal est nécessaire pour cet outil.")
        argv = [terminal, "--hold", f"--working-directory={root}", "--execute", *argv]
    return argv, root


def launch_tool(tool, project):
    argv, root = tool_command(tool, project)
    return subprocess.Popen(argv, cwd=root, stdin=subprocess.DEVNULL,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                            start_new_session=True)
