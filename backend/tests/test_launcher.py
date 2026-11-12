import os,re,subprocess,sys,tempfile,unittest,urllib.request
from pathlib import Path

class TestLaunch(unittest.TestCase):
 def test_new_launcher_serves_html_on_an_available_port(self):
  root=Path(__file__).resolve().parent.parent
  with tempfile.TemporaryDirectory() as tmp:
   env=dict(os.environ,APP_DB=os.path.join(tmp,'demo.sqlite3'))
   proc=subprocess.Popen([sys.executable,'-u','start_focus.py','--no-browser'],cwd=str(root),env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8')
   try:
    address=None
    for _ in range(8):
     line=proc.stdout.readline()
     if not line:break
     m=re.search(r'http://127\.0\.0\.1:\d+/',line)
     if m:address=m.group();break
    self.assertIsNotNone(address,'Сервер не показал адрес')
    with urllib.request.urlopen(address,timeout=5) as result:
     self.assertEqual(result.status,200);self.assertTrue(result.headers['Content-Type'].startswith('text/html'))
     self.assertIn('Focus',result.read().decode())
   finally:
    proc.terminate()
    try:proc.wait(timeout=5)
    except subprocess.TimeoutExpired:proc.kill();proc.wait()
    proc.stdout.close()
