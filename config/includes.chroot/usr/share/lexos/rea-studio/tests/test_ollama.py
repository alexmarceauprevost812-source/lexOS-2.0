import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import threading
import unittest

from rea_studio.ollama import Ollama


class Handler(BaseHTTPRequestHandler):
    mode = 'normal'
    payload = None

    def log_message(self, *args):
        pass

    def respond(self, payload):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        if self.mode == 'redirect':
            self.send_response(302)
            self.send_header('Location', 'http://192.0.2.1/api/tags')
            self.end_headers()
        elif self.mode == 'invalid':
            self.respond(b'not json')
        elif self.mode == 'schema':
            self.respond(b'{"models": [42]}')
        else:
            self.respond(b'{"models": [{"name": "local-test:1"}]}')

    def do_POST(self):
        Handler.payload = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        if self.mode == 'error':
            self.send_response(404)
            self.end_headers()
        else:
            self.respond(b'{"message": {"role": "assistant", "content": "Bonjour"}}')


class OllamaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base = f'http://127.0.0.1:{cls.server.server_port}'

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def setUp(self):
        Handler.mode = 'normal'

    def test_real_http_contract(self):
        client = Ollama(self.base, timeout=1)
        self.assertEqual(client.models(), ['local-test:1'])
        messages = [{'role': 'user', 'content': 'Salut'}]
        self.assertEqual(client.chat('local-test:1', messages), 'Bonjour')
        self.assertEqual(Handler.payload, {'model': 'local-test:1', 'messages': messages, 'stream': False})

    def test_remote_urls_rejected(self):
        for base in ['https://ollama.com', 'http://192.168.1.2:11434', 'file:///tmp/x',
                     'http://localhost@evil.example', 'http://localhost/api', 'http://localhost?remote=yes']:
            with self.subTest(base=base), self.assertRaises(ValueError):
                Ollama(base)

    def test_redirect_refused(self):
        Handler.mode = 'redirect'
        with self.assertRaisesRegex(ValueError, 'HTTP 302'):
            Ollama(self.base).models()

    def test_invalid_json_and_schema(self):
        for mode in ['invalid', 'schema']:
            Handler.mode = mode
            with self.assertRaises(ValueError):
                Ollama(self.base).models()

    def test_missing_model_http_error(self):
        Handler.mode = 'error'
        with self.assertRaisesRegex(ValueError, 'HTTP 404'):
            Ollama(self.base).chat('missing', [])

    def test_server_unavailable(self):
        with self.assertRaisesRegex(ValueError, 'indisponible'):
            Ollama('http://127.0.0.1:1', timeout=0.1).models()
