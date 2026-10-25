"""Production de fichiers à partir d'un plan IA validé, sans écrasement ni shell."""
import ast
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import tempfile

MAX_TOTAL = 1_000_000
EXTENSIONS = {'.py', '.html', '.css', '.js', '.json', '.md', '.txt', '.svg', '.csv'}
SCHEMA = {
    'type': 'object', 'additionalProperties': False,
    'properties': {
        'title': {'type': 'string'},
        'summary': {'type': 'string'},
        'target': {'type': 'string', 'enum': ['desktop', 'web']},
        'entrypoint': {'type': 'string'},
        'files': {'type': 'array', 'items': {
            'type': 'object', 'additionalProperties': False,
            'properties': {'path': {'type': 'string'}, 'content': {'type': 'string'}},
            'required': ['path', 'content']
        }}
    },
    'required': ['title', 'summary', 'target', 'entrypoint', 'files']
}


def validate_plan(plan, expected_target=None):
    if not isinstance(plan, dict) or set(plan) != set(SCHEMA['required']):
        raise ValueError('Le résultat doit contenir title, summary, target, entrypoint et files.')
    for key in ('title', 'summary', 'entrypoint'):
        if not isinstance(plan[key], str) or not plan[key].strip() or len(plan[key]) > 4000:
            raise ValueError(f'Champ invalide : {key}.')
    if plan['target'] not in ('desktop', 'web') or (expected_target and plan['target'] != expected_target):
        raise ValueError('Le type d’application ne correspond pas à la demande.')
    files = plan['files']
    if not isinstance(files, list) or not 1 <= len(files) <= 30:
        raise ValueError('Une application doit contenir entre 1 et 30 fichiers.')
    names = set()
    total = 0
    for item in files:
        if not isinstance(item, dict) or set(item) != {'path', 'content'}:
            raise ValueError('Chaque fichier doit avoir path et content.')
        name, content = item['path'], item['content']
        if not isinstance(name, str) or not isinstance(content, str):
            raise ValueError('Chemin et contenu doivent être du texte.')
        if (not name or len(name) > 240 or '\\' in name or ':' in name
                or any(ord(c) < 32 for c in name) or name.startswith('/')
                or any(part in ('', '.', '..') or part.startswith('.') for part in name.split('/'))):
            raise ValueError(f'Chemin de fichier refusé : {name!r}.')
        path = PurePosixPath(name)
        if path.suffix.lower() not in EXTENSIONS or name == 'rea-project.json':
            raise ValueError(f'Type de fichier refusé : {name}.')
        if name.casefold() in names:
            raise ValueError(f'Fichier dupliqué : {name}.')
        names.add(name.casefold())
        if '\x00' in content:
            raise ValueError(f'Contenu binaire refusé : {name}.')
        total += len(content.encode('utf-8'))
        if total > MAX_TOTAL:
            raise ValueError('Le code dépasse la limite de 1 Mo.')
        if path.suffix == '.py':
            try:
                ast.parse(content, filename=name)
            except SyntaxError as exc:
                raise ValueError(f'Syntaxe Python incorrecte dans {name}, ligne {exc.lineno} : {exc.msg}') from exc
    for name in names:
        if any(str(parent) in names for parent in PurePosixPath(name).parents if str(parent) != '.'):
            raise ValueError('Un fichier est utilisé comme dossier.')
    entry = plan['entrypoint']
    actual_names = {item['path'] for item in files}
    if entry not in actual_names:
        raise ValueError('Le point d’entrée ne correspond à aucun fichier.')
    suffix = '.py' if plan['target'] == 'desktop' else '.html'
    if not entry.endswith(suffix):
        raise ValueError(f'Le point d’entrée doit être un fichier {suffix}.')
    # Retour d'une copie : aucun objet du modèle n'est exécuté.
    return json.loads(json.dumps(plan))


def parse_plan(text, target=None):
    raw = text.strip()
    if raw.startswith('```') and raw.endswith('```'):
        raw = raw.split('\n', 1)[1].rsplit('```', 1)[0]
    try:
        plan = json.loads(raw)
    except (ValueError, TypeError) as exc:
        raise ValueError('La réponse IA ne contient pas un plan JSON complet. Réessayez avec une demande plus courte.') from exc
    return validate_plan(plan, target)


def generation_messages(brief, target, previous=None):
    if target not in ('desktop', 'web') or not brief.strip() or len(brief) > 16000:
        raise ValueError('Décrivez une application en 1 à 16 000 caractères.')
    platform = ('Python 3 avec Tkinter et bibliothèque standard, fenêtre Linux, point d’entrée main.py'
                if target == 'desktop' else 'HTML/CSS/JavaScript sans framework, utilisable en fichier local, point d’entrée index.html')
    instructions = (
        'Tu écris une petite application complète et fonctionnelle pour REA Studio. '
        f'Technologie obligatoire : {platform}. '
        'Interface en français, noire et orange. Aucun sudo, installateur, téléchargement, '
        'commande système, package externe, CDN ou service distant. Ne lance aucun outil. '
        'Ne lis aucun fichier local. Retourne uniquement le JSON demandé, avec les contenus '
        'complets des fichiers (pas de TODO ni de blocs Markdown). Limite-toi à 1 à 5 fichiers '
        'courts et lisibles, avec un README.md qui explique comment lancer l’application. '
        'Les boutons doivent fonctionner. Le code ne doit pas modifier de fichiers en dehors '
        'de son propre dossier. Inclure tous les imports Python nécessaires et lancer mainloop pour Tkinter. '
        'Schéma de sortie : ' + json.dumps(SCHEMA, ensure_ascii=False)
    )
    messages = [{'role': 'system', 'content': instructions}]
    if previous is not None:
        checked = validate_plan(previous, target)
        messages.append({'role': 'user', 'content': 'Voici la version précédente à améliorer :\n' + json.dumps(checked, ensure_ascii=False)})
    messages.append({'role': 'user', 'content': f'Type : {target}\nApplication demandée :\n{brief}'})
    return messages


def generate_application(client, model, brief, target, previous=None):
    messages = generation_messages(brief, target, previous)
    raw = client.structured(model, messages, SCHEMA)
    try:
        return parse_plan(raw, target)
    except ValueError as exc:
        # Une seule réparation bornée ; aucun fichier n'a encore été écrit.
        messages.extend([{'role': 'assistant', 'content': raw[:MAX_TOTAL]},
                         {'role': 'user', 'content': f'Corrige ce problème et renvoie le JSON complet : {exc}'}])
        return parse_plan(client.structured(model, messages, SCHEMA), target)


def save_application(project, plan):
    plan = validate_plan(plan)
    root = Path(project['path']).resolve(strict=True)
    if not root.is_dir():
        raise ValueError('Le dossier du projet est absent.')
    # Construire entièrement dans un dossier neuf, puis publier sans remplacer.
    # Un verrou partagé évite deux noms identiques entre instances REA Studio.
    import fcntl
    with tempfile.TemporaryDirectory(prefix='.rea-build-', dir=root) as temporary:
        staging = Path(temporary) / 'application'
        staging.mkdir()
        for item in plan['files']:
            path = staging / item['path']
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(item['content'], encoding='utf-8')
        (staging / 'rea-project.json').write_text(json.dumps(plan, ensure_ascii=False, indent=2), encoding='utf-8')
        # flock sur le dossier lui-même : pas de fichier verrou issu du projet.
        import os
        descriptor = os.open(root, os.O_RDONLY | os.O_DIRECTORY)
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX)
            for number in range(1, 10000):
                destination = root / ('application' if number == 1 else f'application-{number}')
                if not destination.exists() and not destination.is_symlink():
                    # renameat2 RENAME_NOREPLACE évite aussi une collision extérieure.
                    _rename_new(staging, destination)
                    return destination
            raise ValueError('Trop de versions dans ce projet.')
        finally:
            os.close(descriptor)


def _rename_new(source, destination):
    import ctypes
    import errno
    libc = ctypes.CDLL(None, use_errno=True)
    rename = libc.renameat2
    rename.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    rename.restype = ctypes.c_int
    result = rename(-100, bytes(source), -100, bytes(destination), 1)
    if result != 0:
        code = ctypes.get_errno()
        if code == errno.EEXIST:
            raise FileExistsError('Le dossier de sortie existe déjà. Réessayez.')
        raise OSError(code, 'Impossible de publier les fichiers générés.')


def load_application(directory):
    directory = Path(directory).resolve(strict=True)
    manifest = directory / 'rea-project.json'
    if manifest.is_symlink() or manifest.stat().st_size > 2 * MAX_TOTAL:
        raise ValueError('Description du projet invalide.')
    plan = validate_plan(json.loads(manifest.read_text(encoding='utf-8')))
    # Les fichiers peuvent avoir été édités depuis leur création ; les relire pour l'aperçu.
    for item in plan['files']:
        path = directory / item['path']
        if not path.resolve().is_relative_to(directory) or path.is_symlink() or path.stat().st_size > MAX_TOTAL:
            raise ValueError('Un fichier du projet est absent ou sort du dossier.')
        item['content'] = path.read_text(encoding='utf-8')
    return validate_plan(plan)
