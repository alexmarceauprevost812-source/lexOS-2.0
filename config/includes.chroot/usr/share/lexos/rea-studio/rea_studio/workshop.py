"""Onglet de création d'applications : demande, aperçu, fichiers et lancement."""
from pathlib import Path
import shutil
import subprocess
import sys
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

from .builder import generate_application, load_application, save_application, validate_plan
from .core import launch_tool

EXAMPLE = ('Crée une application de liste de tâches en français. Je veux ajouter une tâche, '
           'la marquer comme terminée et la supprimer. Interface noire et orange, '
           'boutons simples et texte lisible. Application locale sans dépendance externe.')


class Workshop(tk.Frame):
    def __init__(self, parent, app):
        super().__init__(parent, padx=12, pady=10)
        self.app = app
        self.plan = None
        self.saved = None
        self.states = {}
        self.identity = None
        self.target = tk.StringVar(master=self, value='Bureau Linux · Python')
        self.improve = tk.BooleanVar(master=self, value=False)
        self.info = tk.StringVar(master=self, value='Décrivez votre application, puis cliquez sur Générer.')
        row = tk.Frame(self)
        row.pack(fill='x')
        self.target_box = ttk.Combobox(row, textvariable=self.target,
                                      values=['Bureau Linux · Python', 'Application web · HTML'], state='readonly', width=25)
        self.target_box.pack(side='left', padx=(0, 8))
        app.button(row, 'Exemple', self.example)
        app.button(row, 'Ouvrir une version', self.open_version)
        self.brief = app.textbox(self, height=3, expand=False)
        row = tk.Frame(self)
        row.pack(fill='x', pady=4)
        self.generate = app.button(row, 'Générer l’application', self.generate_app, True)
        self.refine = ttk.Checkbutton(row, text='Améliorer la version affichée', variable=self.improve)
        self.refine.pack(side='left')
        self.progress = ttk.Progressbar(self, mode='indeterminate')
        self.progress.pack(fill='x', pady=(0, 4))
        tk.Label(self, textvariable=self.info, anchor='w', justify='left', wraplength=680).pack(fill='x')
        split = tk.PanedWindow(self, orient='horizontal', sashwidth=5, borderwidth=0)
        # Le pied est placé avant l’aperçu pour rester visible en petite fenêtre.
        self.files = tk.Listbox(split, width=19, exportselection=False, bg='#0c0d0f', fg='#f5f5f5',
                                selectbackground='#65391e', highlightthickness=0)
        split.add(self.files, minsize=115)
        code = tk.Frame(split)
        split.add(code, minsize=200)
        self.preview = app.textbox(code, height=6, readonly=True)
        self.files.bind('<<ListboxSelect>>', lambda e: app.guard(self.show_file))
        row = tk.Frame(self)
        row.pack(fill='x')
        self.save = app.button(row, 'Créer les fichiers', self.save_files, True)
        self.run = app.button(row, 'Lancer', self.run_application)
        app.button(row, 'Terminal', self.open_terminal)
        app.button(row, 'Dossier', self.open_folder)
        self.save.configure(state='disabled')
        self.run.configure(state='disabled')
        split.pack(fill='both', expand=True, pady=6)
        row.pack_configure(side='bottom')

    def example(self):
        self.brief.delete('1.0', 'end')
        self.brief.insert('1.0', EXAMPLE)

    def activate(self, project):
        if self.identity:
            self.states[self.identity] = (self.plan, self.saved, self.brief.get('1.0', 'end-1c'), self.target.get())
        self.identity = project['id'] if project else None
        self.plan, self.saved, brief, target = self.states.get(self.identity, (None, None, '', 'Bureau Linux · Python'))
        self.brief.delete('1.0', 'end')
        self.brief.insert('1.0', brief)
        self.target.set(target)
        self.improve.set(False)
        remembered = self.app.settings.get('applications', {}).get(self.identity)
        if not self.plan and project and remembered:
            saved = Path(remembered).resolve()
            if saved.is_relative_to(Path(project['path']).resolve()):
                try:
                    self.plan, self.saved = load_application(saved), saved
                    self.target.set('Bureau Linux · Python' if self.plan['target'] == 'desktop' else 'Application web · HTML')
                except (ValueError, OSError):
                    pass
        self.render()

    def render(self):
        self.files.delete(0, 'end')
        self.preview.configure(state='normal')
        self.preview.delete('1.0', 'end')
        self.preview.configure(state='disabled')
        if self.plan:
            for item in self.plan['files']:
                self.files.insert('end', item['path'])
            self.files.selection_set(0)
            self.show_file()
            self.info.set(self.plan['summary'][:220] + (f'\nEnregistré : {self.saved}' if self.saved else '\nAperçu prêt. Cliquez sur Créer les fichiers.'))
        else:
            self.info.set('Décrivez votre application, puis cliquez sur Générer.')
        self.save.configure(state='normal' if self.plan and not self.saved else 'disabled')
        self.run.configure(state='normal' if self.saved else 'disabled')

    def show_file(self):
        selected = self.files.curselection()
        if self.plan and selected:
            self.preview.configure(state='normal')
            self.preview.delete('1.0', 'end')
            self.preview.insert('1.0', self.plan['files'][selected[0]]['content'])
            self.preview.configure(state='disabled')

    def set_busy(self, busy):
        self.generate.configure(state='disabled' if busy else 'normal')
        if busy:
            self.save.configure(state='disabled')
            self.run.configure(state='disabled')
            self.progress.start(15)
        else:
            self.progress.stop()
            self.save.configure(state='normal' if self.plan and not self.saved else 'disabled')
            self.run.configure(state='normal' if self.saved else 'disabled')

    def generate_app(self):
        if self.app.busy:
            return
        self.app.require_project()
        brief = self.brief.get('1.0', 'end-1c').strip()
        if not brief:
            raise ValueError('Décrivez l’application à créer ou cliquez sur Exemple.')
        if len(brief) > 16000:
            raise ValueError('La demande dépasse 16 000 caractères.')
        target = 'desktop' if self.target.get().startswith('Bureau') else 'web'
        previous = self.plan if self.improve.get() else None
        if self.improve.get() and not previous:
            raise ValueError('Générez ou ouvrez une version avant de demander une amélioration.')
        if previous:
            validate_plan(previous, target)
        client, model = self.app.selected_client(generation=True)
        self.app.persist_preferences()
        provider = self.app.provider.get()
        self.info.set(f'{provider} prépare les fichiers… Cela peut prendre quelques minutes.')
        self.app.status.set('Génération en cours • demande envoyée à ' + provider)
        def done(plan):
            self.plan, self.saved = plan, None
            self.render()
            self.app.status.set(f'{len(plan["files"])} fichiers prêts à créer • aperçu disponible')
        def failed(message):
            self.info.set('Génération échouée. Votre demande et la version précédente sont conservées.')
            messagebox.showerror('Création par IA', message, parent=self.app)
        self.app.background(lambda: generate_application(client, model, brief, target, previous), done, failed)

    def save_files(self):
        if self.app.busy:
            return
        if not self.plan:
            raise ValueError('Générez d’abord une application.')
        self.saved = save_application(self.app.require_project(), self.plan)
        self.remember()
        self.render()
        self.app.status.set('Application créée • ' + str(self.saved))

    def open_version(self):
        if self.app.busy:
            return
        project = self.app.require_project()
        directory = filedialog.askdirectory(title='Ouvrir le dossier application d’une version', initialdir=project['path'], parent=self.app)
        if directory:
            root = Path(project['path']).resolve(strict=True)
            saved = Path(directory).resolve(strict=True)
            if not saved.is_relative_to(root):
                raise ValueError('Choisissez une version à l’intérieur du projet sélectionné.')
            plan = load_application(saved)
            self.plan, self.saved = plan, saved
            self.remember()
            self.target.set('Bureau Linux · Python' if plan['target'] == 'desktop' else 'Application web · HTML')
            self.render()

    def remember(self):
        self.app.settings.setdefault('applications', {})[self.identity] = str(self.saved)
        self.app.persist_preferences()

    def working_directory(self):
        return Path(self.saved or self.app.require_project()['path']).resolve(strict=True)

    def open_folder(self):
        launch_tool({'name': 'Dossier', 'argv': ['xdg-open', '{project}']}, {'path': str(self.working_directory())})

    def open_terminal(self):
        root = self.working_directory()
        terminal = shutil.which('xfce4-terminal')
        if terminal:
            argv = [terminal, f'--working-directory={root}']
        else:
            terminal = shutil.which('x-terminal-emulator')
            if not terminal:
                raise ValueError('Aucun terminal disponible. Installez xfce4-terminal.')
            argv = [terminal]
        process = subprocess.Popen(argv, cwd=root, stdin=subprocess.DEVNULL,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        self.app.tool_processes.append(process)
        self.app.status.set('Terminal ouvert dans le projet • droits de votre compte')

    def run_application(self):
        if not self.saved:
            raise ValueError('Créez les fichiers avant de lancer l’application.')
        plan = load_application(self.saved)
        entry = Path(self.saved) / plan['entrypoint']
        if not messagebox.askyesno('Lancer l’application générée',
                                 f'Lancer {entry.name} ?\n\nLe code affiché sera exécuté avec les droits de votre compte Linux.', parent=self.app):
            return
        if plan['target'] == 'web':
            launch_tool({'name': 'Application web', 'argv': ['xdg-open', str(entry)]}, {'path': str(self.saved)})
        else:
            log_path = Path(self.saved) / 'execution.log'
            # Ne jamais suivre un lien pour le journal d’exécution.
            import os
            fd = os.open(log_path, os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW, 0o600)
            with os.fdopen(fd, 'w') as log:
                process = subprocess.Popen([sys.executable, str(entry)], cwd=self.saved, stdin=subprocess.DEVNULL,
                                           stdout=log, stderr=log, start_new_session=True)
            self.app.tool_processes.append(process)
            self.app.after(900, lambda: self.check_launch(process, log_path))
        self.app.status.set('Application lancée • ' + plan['title'])

    def check_launch(self, process, log_path):
        if process.poll() not in (None, 0):
            try:
                with log_path.open('rb') as log:
                    log.seek(0, 2)
                    log.seek(max(0, log.tell() - 3000))
                    error = log.read().decode('utf-8', errors='replace')
            except OSError:
                error = 'Consultez execution.log dans le dossier de l’application.'
            messagebox.showerror('L’application générée a rencontré une erreur', error, parent=self.app)
