"""Client de l'API officielle Ollama, limité à la boucle locale."""
import json
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, ProxyHandler, Request, build_opener


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class Ollama:
    def __init__(self, base="http://127.0.0.1:11434", timeout=120):
        parsed = urlsplit(base)
        if (parsed.scheme != "http" or parsed.hostname not in ("127.0.0.1", "localhost", "::1")
                or parsed.username or parsed.password or parsed.path not in ("", "/")
                or parsed.query or parsed.fragment):
            raise ValueError("Ollama doit utiliser une adresse HTTP locale, sans chemin ni identifiants.")
        self.base = base.rstrip("/")
        self.timeout = timeout
        # Ignore les proxys système et refuse les redirections hors de la machine.
        self.opener = build_opener(ProxyHandler({}), NoRedirect())

    def request(self, endpoint, payload=None):
        data = None if payload is None else json.dumps(payload).encode("utf-8")
        req = Request(self.base + endpoint, data=data, headers={"Content-Type": "application/json"})
        try:
            with self.opener.open(req, timeout=self.timeout) as response:
                raw = response.read(8_000_001)
                if len(raw) > 8_000_000:
                    raise ValueError("Réponse Ollama trop volumineuse.")
                result = json.loads(raw)
                if not isinstance(result, dict):
                    raise ValueError("Réponse Ollama invalide.")
                if result.get("error"):
                    raise ValueError(str(result["error"]))
                return result
        except HTTPError as exc:
            raise ValueError(f"Ollama : erreur HTTP {exc.code}. Vérifiez le modèle et le serveur.") from exc
        except (URLError, TimeoutError, OSError) as exc:
            raise ValueError("Ollama indisponible ou délai dépassé. Vérifiez 'ollama serve'.") from exc
        except (json.JSONDecodeError, UnicodeError) as exc:
            raise ValueError("Le serveur n'a pas renvoyé un JSON Ollama valide.") from exc

    def models(self):
        models = self.request("/api/tags").get("models")
        if not isinstance(models, list) or any(not isinstance(m, dict) or not isinstance(m.get("name"), str) for m in models):
            raise ValueError("Liste de modèles Ollama invalide.")
        return [m["name"] for m in models]

    def chat(self, model, messages):
        if not model.strip():
            raise ValueError("Choisissez un modèle installé.")
        value = self.request("/api/chat", {"model": model, "messages": messages, "stream": False})
        message = value.get("message")
        if not isinstance(message, dict) or not isinstance(message.get("content"), str):
            raise ValueError("Message Ollama invalide.")
        return message["content"]
