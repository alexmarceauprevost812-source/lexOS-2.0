"""IA en ligne via le CLI Codex authentifié de l'utilisateur."""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile


def codex_executable():
    executable = shutil.which('codex')
    fallback = Path.home() / '.local/bin/codex'
    if not executable and fallback.is_file() and os.access(fallback, os.X_OK):
        executable = str(fallback)
    if not executable:
        raise ValueError('Codex est absent. Installez le CLI Codex puis connectez-vous avec codex login.')
    return executable


class Codex:
    def __init__(self, timeout=600):
        self.timeout = timeout

    def structured(self, model, messages, schema):
        executable = codex_executable()
        with tempfile.TemporaryDirectory(prefix='rea-codex-') as temporary:
            root = Path(temporary)
            schema_file, answer_file = root / 'schema.json', root / 'answer.json'
            schema_file.write_text(json.dumps(schema), encoding='utf-8')
            prompt = ('Produis uniquement la réponse finale au schéma demandé. '
                      'Aucun outil, aucune commande et aucune lecture de fichiers ne sont nécessaires.\n\n'
                      + '\n\n'.join(m['role'].upper() + ':\n' + m['content'] for m in messages))
            argv = [executable, 'exec', '--ignore-user-config', '--sandbox', 'read-only',
                    '--skip-git-repo-check', '--ephemeral', '--color', 'never',
                    '--output-schema', str(schema_file), '--output-last-message', str(answer_file),
                    '--cd', str(root), '-']
            with (root / 'diagnostic.log').open('w+', encoding='utf-8') as log:
                process = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=log, stderr=log,
                                           text=True, cwd=root, start_new_session=True)
                try:
                    process.communicate(prompt, timeout=self.timeout)
                except subprocess.TimeoutExpired as exc:
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait()
                    raise ValueError('Codex a dépassé le délai de 10 minutes. Réessayez avec une demande plus courte.') from exc
                if process.returncode or not answer_file.exists():
                    log.seek(0, 2)
                    size = log.tell()
                    log.seek(max(0, size - 1500))
                    diagnostic = log.read()
                    raise ValueError('Codex en ligne indisponible. Vérifiez Internet et codex login.\n' + diagnostic[-1000:])
                if answer_file.stat().st_size > 2_000_000:
                    raise ValueError('La réponse Codex est trop volumineuse.')
                return answer_file.read_text(encoding='utf-8')

    def chat(self, model, messages):
        schema = {'type': 'object', 'additionalProperties': False,
                  'properties': {'content': {'type': 'string'}}, 'required': ['content']}
        value = json.loads(self.structured(model, messages, schema))
        if not isinstance(value, dict) or not isinstance(value.get('content'), str):
            raise ValueError('Réponse Codex invalide.')
        return value['content']
