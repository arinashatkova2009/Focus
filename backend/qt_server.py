"""Private desktop transport. Existing application rules stay in app.py."""
import hmac
import json
import os
import sys
import threading
from pathlib import Path
from storage_crypto import seal,unseal
from http.server import ThreadingHTTPServer


def main():
    config = json.loads(sys.stdin.readline())
    vault=Path(os.environ.get('APP_DB','app.sqlite3')).resolve().parent/'cloud-connection.json'
    if config.get('loadSaved',True) and not config.get('key') and vault.exists():
        try:
            saved=json.loads(unseal(vault.read_text(encoding='utf-8')))
            if saved.get('provider')==config.get('provider') and saved.get('consent'):
                config.update({k:saved[k] for k in ('key','model','consent')})
            saved.clear()
        except (ValueError,OSError,RuntimeError):pass
    if config.get('remember') and config.get('key') and config.get('consent'):
        vault.parent.mkdir(parents=True,exist_ok=True)
        vault.write_text(seal(json.dumps({k:config[k] for k in ('provider','model','key','consent')})),encoding='utf-8')
    provider = config.get('provider', 'ollama')
    if provider not in ('ollama', 'openai', 'anthropic', 'gemini'):
        raise ValueError('Unknown provider')
    for key in list(os.environ):
        if key.startswith('FOCUS_AGENT_') or key in (
            'OPENAI_API_KEY', 'ANTHROPIC_API_KEY', 'GEMINI_API_KEY',
            'FOCUS_ALLOW_EXTERNAL', 'EXTERNAL_DEMO_ONLY',
            'EXTERNAL_NO_TRAINING_CONFIRMED', 'EXTERNAL_NO_CONTENT_STORAGE_CONFIRMED'):
            os.environ.pop(key, None)
    os.environ['FOCUS_DEFAULT_PROVIDER'] = provider
    os.environ['FOCUS_ALLOW_EXTERNAL'] = '1' if config.get('consent') else '0'
    key_names = {'openai': 'OPENAI_API_KEY', 'anthropic': 'ANTHROPIC_API_KEY', 'gemini': 'GEMINI_API_KEY'}
    if provider in key_names:
        os.environ[key_names[provider]] = config.get('key', '')
    if config.get('model'):
        os.environ[provider.upper() + '_MODEL'] = config['model']
    secret = config['secret']
    if not isinstance(secret, str) or len(secret) < 32:
        raise ValueError('Desktop secret required')
    config.clear()
    import app
    import store

    class DesktopHandler(app.Handler):
        def authorized(self):
            supplied = self.headers.get('X-Focus-Desktop-Key', '')
            if not hmac.compare_digest(supplied.encode(), secret.encode()):
                self.send(403, {'error': 'Доступ разрешён только приложению Focus.'})
                return False
            return True

        def do_GET(self):
            if self.authorized():
                self.handle_request('GET')

        def do_POST(self):
            if self.authorized():
                self.handle_request('POST')

    store.seed()
    server = ThreadingHTTPServer(('127.0.0.1', 0), DesktopHandler)
    server.daemon_threads = True

    def monitor_parent():
        for _ in sys.stdin:
            pass
        server.shutdown()

    threading.Thread(target=monitor_parent, daemon=True).start()
    print('FOCUS_READY', server.server_port, flush=True)
    try:
        server.serve_forever(poll_interval=0.1)
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
