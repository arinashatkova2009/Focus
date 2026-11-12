import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest
import urllib.error
import urllib.request

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from local_files import file_identity


class DesktopTests(unittest.TestCase):
    def test_wide_windows_file_identity_is_lossless_in_sqlite(self):
        with sqlite3.connect(':memory:') as db:
            db.execute('CREATE TABLE ids (ino INTEGER)')
            first = (1 << 120) + 123
            second = first + 1
            db.executemany('INSERT INTO ids VALUES (?)', [(file_identity(first),), (file_identity(second),)])
            values = [row[0] for row in db.execute('SELECT ino FROM ids')]
            self.assertEqual(values, [file_identity(first), file_identity(second)])
            self.assertNotEqual(values[0], values[1])
            self.assertEqual(file_identity(42), 42)

    def test_private_transport_and_parent_shutdown(self):
        root = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as tmp:
            env = dict(os.environ, APP_DB=str(Path(tmp) / 'demo.sqlite3'), PYTHONUTF8='1')
            proc = subprocess.Popen([sys.executable, '-u', str(root / 'qt_server.py')],
                                    cwd=root, env=env, stdin=subprocess.PIPE,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding='utf-8')
            try:
                secret = 'desktop-test-secret-' * 4
                proc.stdin.write(json.dumps({'provider':'ollama', 'model':'llama3.1', 'secret':secret}) + '\n')
                proc.stdin.flush()
                line = proc.stdout.readline()
                self.assertTrue(line.startswith('FOCUS_READY '), line)
                base = 'http://127.0.0.1:' + line.split()[1]
                with self.assertRaises(urllib.error.HTTPError) as rejected:
                    urllib.request.urlopen(base + '/health', timeout=5)
                self.assertEqual(rejected.exception.code, 403)
                request = urllib.request.Request(base + '/health', headers={'X-Focus-Desktop-Key':secret})
                with urllib.request.urlopen(request, timeout=5) as result:
                    self.assertEqual(json.load(result)['status'], 'ok')
                proc.stdin.close()
                self.assertEqual(proc.wait(timeout=5), 0)
            finally:
                if proc.poll() is None:
                    proc.kill(); proc.wait()
                for pipe in (proc.stdin, proc.stdout, proc.stderr):
                    pipe.close()


if __name__ == '__main__':
    unittest.main()
