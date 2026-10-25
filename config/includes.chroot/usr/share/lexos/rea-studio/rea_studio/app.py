"""Fenêtre Tk ; les travailleurs ne touchent jamais aux widgets."""
import json
import os
from pathlib import Path
import queue
import shlex
import threading
import tkinter as tk
from tkinter import filedialog, messagebox, simpledialog, ttk

from .core import DEFAULT_TOOLS, Projects, atomic_write, launch_tool, note_path, read_json, tool_command, validate_tools
from .ollama import Ollama
from .providers import Codex
from .workshop import Workshop
from . import __version__

BG, PANEL, TEXT, MUTED, ORANGE = "#0c0d0f", "#17191d", "#f5f5f5", "#b2b5bc", "#ff8a32"


class Studio(tk.Tk):
    def __init__(self, data_dir=None, config_dir=None):
        super().__init__()
        self.title("REA Studio • LexOS Pro")
        self.geometry("1120x760")
        self.minsize(900, 700)
        self.configure(bg=BG)
        icon_path = Path(__file__).resolve().parent.parent / "assets/rea-studio.png"
        if icon_path.exists():
            self._icon = tk.PhotoImage(master=self, file=str(icon_path))
            self.iconphoto(True, self._icon)
        self.projects = Projects(data_dir)
        self.config_dir = Path(config_dir or Path(os.getenv("XDG_CONFIG_HOME", Path.home() / ".config")) / "rea-studio")
        self.current = None
        self.dirty = False
        self.busy = False
        self.events = queue.Queue()
        self.histories = {}
        self.tool_processes = []
        self.settings = read_json(self.config_dir / "settings.json", {})
        if not isinstance(self.settings, dict):
            raise ValueError("Réglages invalides ; fichier conservé.")
        self.tools = validate_tools(read_json(self.config_dir / "tools.json", DEFAULT_TOOLS))
        self.provider = tk.StringVar(master=self, value=self.settings.get("provider", "Ollama local"))
        self._style()
        self._build()
        self.reload_projects()
        last = self.settings.get("last_project")
        if last in self.records and Path(self.records[last]["path"]).is_dir():
            self.project_list.selection_set(last)
            self._select_project()
        self._poll_id = self.after(80, self.poll)
        self.protocol("WM_DELETE_WINDOW", self.close)
        self.bind("<Control-s>", lambda e: self.guard(self.save_notes))

    def _style(self):
        self.option_add("*Font", "{DejaVu Sans} 10")
        self.option_add("*Background", PANEL)
        self.option_add("*Foreground", TEXT)
        self.option_add("*selectBackground", "#80451d")
        style = ttk.Style(self)
        style.theme_use("clam")
        style.configure(".", background=PANEL, foreground=TEXT, fieldbackground=BG)
        style.configure("TButton", padding=(12, 8), borderwidth=0)
        style.map("TButton", background=[("active", "#38322c")], foreground=[("disabled", "#777777")])
        style.configure("Accent.TButton", background=ORANGE, foreground="#111111")
        style.map("Accent.TButton", background=[("active", "#ffac6c")], foreground=[("disabled", "#555555")])
        style.configure("TNotebook", background=BG, borderwidth=0)
        style.configure("TNotebook.Tab", padding=(12, 10))
        style.map("TNotebook.Tab", background=[("selected", "#32302b")], foreground=[("selected", ORANGE)])
        style.configure("Treeview", background=BG, fieldbackground=BG, rowheight=34)
        style.map("Treeview", background=[("selected", "#65391e")])
        style.configure("TEntry", insertcolor=TEXT)
        style.map("TCombobox", fieldbackground=[("readonly", BG)], foreground=[("readonly", TEXT)], selectbackground=[("readonly", BG)], selectforeground=[("readonly", TEXT)])

    def label(self, parent, text, size=10, color=TEXT, **kwargs):
        return tk.Label(parent, text=text, font=("DejaVu Sans", size), fg=color, anchor="w", **kwargs)

    def button(self, parent, text, command, accent=False):
        widget = ttk.Button(parent, text=text, command=lambda: self.guard(command), style="Accent.TButton" if accent else "TButton")
        widget.pack(side="left", padx=(0, 8), pady=4)
        return widget

    def _build(self):
        top = tk.Frame(self, bg=BG)
        top.pack(fill="x", padx=24, pady=(20, 14))
        self.label(top, "REA", 25, ORANGE, bg=BG).pack(side="left")
        self.label(top, "  STUDIO", 25, bg=BG).pack(side="left")
        self.label(top, "LEXOS PRO  /  ATELIER LOCAL", 10, MUTED, bg=BG).pack(side="right")
        body = tk.PanedWindow(self, orient="horizontal", bg=BG, sashwidth=6, borderwidth=0)
        body.pack(fill="both", expand=True, padx=20)
        side = tk.Frame(body, bg=PANEL, padx=14, pady=14)
        body.add(side, width=265, minsize=235)
        self.label(side, "MES PROJETS", 11, ORANGE).pack(fill="x", pady=(0, 10))
        self.project_list = ttk.Treeview(side, show="tree", selectmode="browse", height=9)
        self.project_list.pack(fill="both", expand=True)
        self.project_list.bind("<<TreeviewSelect>>", self.select_project)
        for text, callback in [("+ Nouveau projet", self.new_project), ("Importer un dossier", self.import_project),
                               ("Renommer", self.rename_project), ("Retirer de la liste", self.forget_project)]:
            ttk.Button(side, text=text, command=lambda f=callback: self.guard(f)).pack(fill="x", pady=(8, 0))
        self.label(side, "Données sur cet ordinateur", 9, MUTED).pack(fill="x", pady=(16, 0))
        main = tk.Frame(body, bg=BG, padx=12)
        body.add(main, minsize=500)
        self.project_title = self.label(main, "Votre prochain projet commence ici", 18, bg=BG)
        self.project_title.pack(fill="x", pady=(8, 4))
        self.project_path = self.label(main, "Créez un projet ou importez un dossier existant.", 9, MUTED, bg=BG, wraplength=650)
        self.project_path.pack(fill="x", pady=(0, 16))
        choices = tk.Frame(main, bg=BG)
        choices.pack(fill="x", pady=(0, 6))
        self.provider_box = ttk.Combobox(choices, textvariable=self.provider,
                                         values=["Ollama local", "Codex en ligne"], state="readonly", width=17)
        self.provider_box.pack(side="left", padx=(0, 8))
        self.provider_box.bind("<<ComboboxSelected>>", lambda e: self.provider_changed())
        self.model = tk.StringVar(master=self, value=self.settings.get("model", ""))
        self.models = ttk.Combobox(choices, textvariable=self.model, state="readonly", width=18)
        self.models.pack(side="left", fill="x", expand=True)
        self.refresh_button = self.button(choices, "Modèles", self.refresh_models)
        self.button(choices, "Connexion", self.connection)
        self.privacy = self.label(main, "Ollama local : génération sur votre ordinateur.", 9, MUTED, bg=BG, wraplength=680)
        self.privacy.pack(fill="x", pady=(0, 8))
        notebook = self.notebook = ttk.Notebook(main)
        notebook.pack(fill="both", expand=True)
        self.workshop = Workshop(notebook, self)
        notebook.add(self.workshop, text="Créer avec l’IA")
        notes, ai, tools = [tk.Frame(notebook, padx=16, pady=16) for _ in range(3)]
        for frame, name in [(notes, "Notes du projet"), (ai, "Discussion IA"), (tools, "Outils REA")]:
            notebook.add(frame, text=name)
        self.label(notes, "Idées, objectifs et prochaines étapes", 12).pack(fill="x", pady=(0, 8))
        self.notes = self.textbox(notes)
        self.notes.bind("<<Modified>>", self.modified)
        bar = tk.Frame(notes)
        bar.pack(fill="x", pady=(10, 0))
        self.button(bar, "Enregistrer · Ctrl+S", self.save_notes, True)
        self.button(bar, "Ouvrir le dossier", self.open_project)
        self.label(notes, "Enregistré dans .rea-studio/notes.md du projet.", 9, MUTED).pack(fill="x", pady=(8, 0))
        self.label(ai, "Discutez avec le moteur choisi ci-dessus. Les fichiers ne sont pas lus automatiquement.", 9, MUTED, wraplength=620).pack(fill="x", pady=8)
        self.conversation = self.textbox(ai, height=7, readonly=True)
        self.prompt = self.textbox(ai, height=3, expand=False)
        self.prompt.bind("<Control-Return>", lambda e: self.guard(self.send))
        bar = tk.Frame(ai)
        bar.pack(fill="x", pady=(8, 0))
        self.send_button = self.button(bar, "Envoyer · Ctrl+Entrée", self.send, True)
        self.clear_button = self.button(bar, "Nouvelle discussion", self.clear_chat)
        self.button(bar, "Exporter", self.export_chat)
        self.label(tools, "Connectez vos outils à l’atelier", 15).pack(fill="x")
        self.label(tools, "REA reste à identifier. Ajoutez ici une commande réelle déjà installée.\nChaque lancement est explicite ; aucune commande ne vient de l’IA.", 10, MUTED, wraplength=620, justify="left").pack(fill="x", pady=(8, 12))
        self.tool_list = tk.Listbox(tools, bg=BG, fg=TEXT, selectbackground="#65391e", highlightthickness=0, exportselection=False)
        self.tool_list.pack(fill="both", expand=True)
        self.populate_tools()
        bar = tk.Frame(tools)
        bar.pack(fill="x", pady=10)
        self.button(bar, "Lancer l’outil", self.run_tool, True)
        self.button(bar, "Configurer", self.configure_tools)
        self.label(tools, "Les outils absents sont signalés. Aucune installation automatique.", 9, MUTED).pack(fill="x")
        self.status = tk.StringVar(master=self, value="Prêt • REA Studio " + __version__)
        tk.Label(self, textvariable=self.status, bg=BG, fg=MUTED, anchor="w", padx=24, pady=12).pack(fill="x")

    def textbox(self, parent, height=12, readonly=False, expand=True):
        frame = tk.Frame(parent)
        frame.pack(fill="both" if expand else "x", expand=expand, pady=(4, 0))
        text = tk.Text(frame, bg=BG, fg=TEXT, insertbackground=ORANGE, selectbackground="#65391e", wrap="word", height=height,
                       relief="flat", padx=12, pady=12, undo=True, font=("DejaVu Sans Mono", 10))
        scroll = ttk.Scrollbar(frame, command=text.yview)
        scroll.pack(side="right", fill="y")
        text.pack(fill="both", expand=True)
        text.configure(yscrollcommand=scroll.set)
        if readonly:
            text.configure(state="disabled")
        return text

    def guard(self, action):
        try:
            return action()
        except (ValueError, OSError) as exc:
            messagebox.showerror("REA Studio", str(exc), parent=self)

    def reload_projects(self):
        self.records = {p["id"]: p for p in self.projects.list()}
        self.project_list.delete(*self.project_list.get_children())
        for p in self.records.values():
            suffix = " (absent)" if not Path(p["path"]).is_dir() else ""
            self.project_list.insert("", "end", iid=p["id"], text=p["name"] + suffix)

    def require_project(self):
        if not self.current:
            raise ValueError("Créez ou sélectionnez un projet d’abord.")
        return self.current

    def can_leave(self):
        if not self.dirty:
            return True
        answer = messagebox.askyesnocancel("Notes modifiées", "Enregistrer les notes avant de continuer ?", parent=self)
        if answer is None:
            return False
        if answer:
            self.save_notes()
        return True

    def select_project(self, event=None):
        self.guard(self._select_project)

    def _select_project(self):
        selection = self.project_list.selection()
        if not selection:
            return
        project = self.records[selection[0]]
        if self.current and project["id"] == self.current["id"]:
            return
        if self.busy or not self.can_leave():
            if self.current:
                self.project_list.selection_set(self.current["id"])
            self.status.set("Terminez la réponse IA avant de changer de projet." if self.busy else "Changement annulé.")
            return
        path = note_path(project)
        content = path.read_text(encoding="utf-8") if path.exists() else ""
        self.current = project
        self.project_title.configure(text=project["name"])
        self.project_path.configure(text=project["path"])
        self.notes.delete("1.0", "end")
        self.notes.insert("1.0", content)
        self.notes.edit_modified(False)
        self.dirty = False
        self.prompt.delete("1.0", "end")
        self.render_chat()
        self.workshop.activate(project)
        self.settings["last_project"] = project["id"]
        self.persist_preferences()
        self.status.set("Projet ouvert • " + project["name"])

    def choose(self, project):
        self.reload_projects()
        self.project_list.selection_set(project["id"])
        self._select_project()

    def new_project(self):
        if self.busy:
            raise ValueError("Attendez la fin de la réponse IA.")
        projects_dir = Path.home() / "Documents" / "REA Studio"
        projects_dir.mkdir(parents=True, exist_ok=True)
        parent = filedialog.askdirectory(title="Dossier parent du nouveau projet", initialdir=projects_dir, parent=self)
        if parent:
            name = simpledialog.askstring("Nouveau projet", "Nom du nouveau dossier :", parent=self)
            if name:
                self.choose(self.projects.create(parent, name))

    def import_project(self):
        if self.busy:
            raise ValueError("Attendez la fin de la réponse IA.")
        directory = filedialog.askdirectory(title="Importer un dossier de projet", parent=self)
        if directory:
            self.choose(self.projects.add(directory))

    def rename_project(self):
        p = self.require_project()
        name = simpledialog.askstring("Renommer", "Nom affiché (le dossier garde son nom) :", initialvalue=p["name"], parent=self)
        if name:
            self.projects.rename(p["id"], name)
            p["name"] = name.strip()
            self.project_title.configure(text=p["name"])
            self.reload_projects()
            self.project_list.selection_set(p["id"])

    def forget_project(self):
        p = self.require_project()
        if self.busy or not self.can_leave():
            return
        if messagebox.askyesno("Retirer le projet", "Retirer ce projet de la liste ? Le dossier et ses notes seront conservés.", parent=self):
            self.projects.forget(p["id"])
            self.current = None
            self.workshop.activate(None)
            self.notes.delete("1.0", "end")
            self.notes.edit_modified(False)
            self.dirty = False
            self.project_title.configure(text="Sélectionnez un projet")
            self.project_path.configure(text="Le dossier retiré est conservé.")
            self.prompt.delete("1.0", "end")
            self.render_chat()
            self.reload_projects()

    def modified(self, event=None):
        if self.notes.edit_modified():
            self.dirty = True
            self.status.set("Notes modifiées • à enregistrer")
            self.notes.edit_modified(False)

    def save_notes(self):
        p = self.require_project()
        atomic_write(note_path(p), self.notes.get("1.0", "end-1c"))
        self.dirty = False
        self.status.set("Notes enregistrées • " + p["name"])

    def open_project(self):
        launch_tool(DEFAULT_TOOLS[0], self.require_project())

    def client(self):
        return Ollama(self.settings.get("ollama_url", "http://127.0.0.1:11434"))

    def connection(self):
        if self.busy:
            raise ValueError("Attendez la fin de la requête IA.")
        if self.provider.get() == "Codex en ligne":
            messagebox.showinfo("Codex en ligne", "Utilise la connexion du programme Codex installé sur cet ordinateur.\nInternet et un compte connecté sont nécessaires.\nPour connecter un autre poste : lancer codex login dans son terminal.", parent=self)
            return
        url = simpledialog.askstring("Ollama local", "Adresse HTTP locale du serveur :", initialvalue=self.client().base, parent=self)
        if url:
            Ollama(url)
            settings = {**self.settings, "ollama_url": url}
            atomic_write(self.config_dir / "settings.json", json.dumps(settings, indent=2))
            self.settings = settings
            self.models["values"] = ()
            self.model.set("")
            self.status.set("Connexion enregistrée • détectez les modèles")

    def persist_preferences(self):
        self.settings["model"] = self.model.get()
        self.settings["provider"] = self.provider.get()
        atomic_write(self.config_dir / "settings.json", json.dumps(self.settings, ensure_ascii=False, indent=2))

    def provider_changed(self):
        online = self.provider.get() == "Codex en ligne"
        self.models.configure(state="disabled" if online else "readonly")
        self.privacy.configure(text=("Codex en ligne : votre demande et la version à améliorer sont envoyées à OpenAI."
                                     if online else "Ollama local : génération sur votre ordinateur."))
        self.guard(self.persist_preferences)

    def selected_client(self, generation=False):
        if self.provider.get() == "Codex en ligne":
            return Codex(), ""
        model = self.model.get()
        if not model or model not in self.models["values"]:
            raise ValueError("Cliquez sur Modèles puis choisissez un modèle Ollama installé.")
        return Ollama(self.settings.get("ollama_url", "http://127.0.0.1:11434"),
                      timeout=600 if generation else 120), model

    def background(self, action, done, on_error=None):
        self.busy = True
        for widget in (self.send_button, self.refresh_button, self.clear_button, self.provider_box):
            widget.configure(state="disabled")
        self.workshop.set_busy(True)
        def worker():
            try:
                result = (True, action())
            except Exception as exc:
                result = (False, str(exc))
            self.events.put((done, result, on_error))
        threading.Thread(target=worker, daemon=True).start()

    def poll(self):
        try:
            while True:
                done, (success, value), on_error = self.events.get_nowait()
                self.busy = False
                for widget in (self.send_button, self.refresh_button, self.clear_button):
                    widget.configure(state="normal")
                self.provider_box.configure(state="readonly")
                self.workshop.set_busy(False)
                if success:
                    self.guard(lambda: done(value))
                else:
                    self.status.set("Échec • " + value)
                    if on_error:
                        on_error(value)
                    else:
                        messagebox.showerror("IA", value, parent=self)
        except queue.Empty:
            pass
        self.tool_processes[:] = [p for p in self.tool_processes if p.poll() is None]
        self._poll_id = self.after(80, self.poll)

    def refresh_models(self, silent=False):
        if self.busy:
            return
        client = self.client()
        self.status.set("Recherche du serveur Ollama local…")
        def done(models):
            self.models["values"] = models
            if self.model.get() not in models:
                preferred = next((m for m in models if m.startswith("qwen2.5-coder:7b")), models[0] if models else "")
                self.model.set(preferred)
            self.status.set(f"Ollama connecté • {len(models)} modèle(s) installé(s)" if models else "Aucun modèle installé. Utilisez ollama pull NOM_DU_MODELE dans un terminal.")
        self.background(client.models, done, (lambda error: None) if silent else None)

    def history(self):
        return self.histories.setdefault(self.require_project()["id"], [])

    def render_chat(self):
        self.conversation.configure(state="normal")
        self.conversation.delete("1.0", "end")
        history = self.histories.get(self.current["id"], []) if self.current else []
        for msg in history:
            self.conversation.insert("end", ("VOUS" if msg["role"] == "user" else "IA") + "\n" + msg["content"] + "\n\n")
        self.conversation.configure(state="disabled")
        self.conversation.see("end")

    def send(self):
        if self.busy:
            return
        history = self.history()
        prompt = self.prompt.get("1.0", "end-1c").strip()
        if not prompt:
            return
        client, model = self.selected_client()
        pending = {"role": "user", "content": prompt}
        messages = [{"role": "system", "content": "Tu aides à créer des projets dans REA Studio. REA n'a pas d'API définie. Ne prétends jamais avoir exécuté des commandes ni modifié des fichiers."}, *history, pending]
        self.persist_preferences()
        self.status.set(self.provider.get() + " réfléchit…")
        def done(reply):
            history.extend([pending, {"role": "assistant", "content": reply}])
            # Ne pas supprimer un nouveau brouillon rédigé pendant la génération.
            if self.prompt.get("1.0", "end-1c").strip() == prompt:
                self.prompt.delete("1.0", "end")
            self.render_chat()
            self.status.set("Réponse reçue • aucun fichier modifié")
        self.background(lambda: client.chat(model, messages), done)

    def clear_chat(self):
        if not self.busy:
            self.histories[self.require_project()["id"]] = []
            self.render_chat()

    def export_chat(self):
        history = self.history()
        if not history:
            raise ValueError("La discussion est vide.")
        path = filedialog.asksaveasfilename(title="Exporter la discussion", defaultextension=".md", initialfile="discussion-rea.md", parent=self)
        if path:
            atomic_write(path, "\n\n".join("## " + m["role"] + "\n\n" + m["content"] for m in history) + "\n")
            self.status.set("Discussion exportée")

    def populate_tools(self):
        self.tool_list.delete(0, "end")
        for tool in self.tools:
            self.tool_list.insert("end", tool["name"])

    def run_tool(self):
        project = self.require_project()
        selected = self.tool_list.curselection()
        if not selected:
            raise ValueError("Sélectionnez un outil.")
        tool = self.tools[selected[0]]
        argv, root = tool_command(tool, project)
        if messagebox.askyesno("Lancer cet outil", f"Dossier : {root}\n\nCommande :\n{shlex.join(argv)}\n\nCet outil dispose des droits de votre session. Continuer ?", parent=self):
            self.tool_processes.append(launch_tool(tool, project))
            self.status.set("Processus lancé • " + tool["name"])

    def configure_tools(self):
        window = tk.Toplevel(self)
        window.title("Outils REA • configuration utilisateur")
        window.geometry("720x500")
        self.label(window, 'Liste JSON : name, argv (arguments séparés), terminal. {project} = dossier sélectionné.', 10, MUTED, wraplength=680).pack(padx=14, pady=14)
        editor = self.textbox(window)
        editor.insert("1.0", json.dumps(self.tools, ensure_ascii=False, indent=2))
        def save():
            tools = validate_tools(json.loads(editor.get("1.0", "end-1c")))
            atomic_write(self.config_dir / "tools.json", json.dumps(tools, ensure_ascii=False, indent=2))
            self.tools = tools
            self.populate_tools()
            window.destroy()
        ttk.Button(window, text="Enregistrer la configuration", command=lambda: self.guard(save)).pack(pady=12)

    def destroy(self):
        if getattr(self, "_poll_id", None):
            self.after_cancel(self._poll_id)
            self._poll_id = None
        super().destroy()

    def close(self):
        try:
            if self.busy and not messagebox.askyesno("Réponse en cours", "Fermer la fenêtre ? La réponse en cours sera abandonnée et les discussions non exportées seront perdues.", parent=self):
                return
            if self.can_leave():
                self.destroy()
        except (ValueError, OSError) as exc:
            messagebox.showerror("Enregistrement impossible", str(exc), parent=self)


def main():
    try:
        app = Studio()
        app.provider_changed()
        app.after(200, lambda: app.refresh_models(silent=True))
        app.mainloop()
    except tk.TclError as exc:
        raise SystemExit(f"Impossible d’ouvrir la fenêtre. Lancez REA Studio depuis une session graphique XFCE.\n{exc}") from exc
    except (ValueError, OSError) as exc:
        raise SystemExit(f"REA Studio : {exc}") from exc
