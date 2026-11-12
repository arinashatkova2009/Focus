import json, os, sys, tempfile, threading, unittest, urllib.request, urllib.error
from unittest.mock import patch
from contextlib import closing
from http.server import ThreadingHTTPServer
sys.path.insert(0,os.path.dirname(os.path.dirname(__file__)))
import app, store, providers

class AgentRuntimeTest(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.tmp=tempfile.TemporaryDirectory();cls.orig=store.DB_PATH;store.DB_PATH=os.path.join(cls.tmp.name,'demo.db');store.seed();cls.server=ThreadingHTTPServer(('127.0.0.1',0),app.Handler);threading.Thread(target=cls.server.serve_forever,daemon=True).start();cls.base='http://127.0.0.1:'+str(cls.server.server_port)
  cls.token=cls.request('/auth/login',{'username':'employee','password':'Employee-demo-2026!'})[1]['token']
 @classmethod
 def tearDownClass(cls):cls.server.shutdown();cls.server.server_close();store.DB_PATH=cls.orig;cls.tmp.cleanup()
 @classmethod
 def request(cls,path,body=None,token=None):
  h={'Content-Type':'application/json'}
  if token:h['Authorization']='Bearer '+token
  req=urllib.request.Request(cls.base+path,headers=h,data=json.dumps(body,ensure_ascii=False).encode() if body is not None else None)
  try:
   with urllib.request.urlopen(req,timeout=10) as r:return r.status,json.load(r)
  except urllib.error.HTTPError as e:return e.code,json.load(e)
 def agent(self,text,agent='eva',history=None):return self.request('/focus/agent',{'text':text,'agent':agent,'history':history or []},self.token)
 def test_human_chat_uses_context_and_model(self):
  plan=json.dumps({'agent':'nick','action':'answer','args':{},'answer':'Привет! У меня всё хорошо. Чем помочь?'},ensure_ascii=False)
  with patch('providers.generate',return_value=plan) as gen:
   code,result=self.agent('Как дела?','nick',[{'role':'user','text':'Я готовлю встречу'}]);self.assertEqual(code,200);self.assertEqual(result['answer'],'Привет! У меня всё хорошо. Чем помочь?');self.assertIn('Я готовлю встречу',gen.call_args.args[1]);self.assertFalse(result['handoff'])
 def test_handoff_and_data_are_scoped(self):
  plan=json.dumps({'agent':'nick','action':'search_documents','args':{'query':'Тестовый документ'},'answer':''},ensure_ascii=False)
  def generate(provider,prompt,sources='',model=None):
   if 'Верни строго один JSON' in prompt:return plan
   self.assertIn('Тестовый документ',sources);self.assertNotIn('Продажи',sources);return 'Нашёл доступные документы.'
  with patch('providers.generate',side_effect=generate):
   code,r=self.agent('Найди тестовый документ','nick');self.assertEqual(code,200);self.assertEqual(r['agent'],'robby');self.assertTrue(r['handoff']);self.assertTrue(r['sources']);self.assertLessEqual(len(r['sources']),12)
 def test_task_draft_does_not_write(self):
  plan=json.dumps({'agent':'leo','action':'draft_task','args':{'title':'Сделать отчёт'},'answer':'ok'},ensure_ascii=False)
  with closing(store.connect()) as c:before=c.execute('SELECT count(*) FROM objects').fetchone()[0]
  with patch('providers.generate',return_value=plan):
   code,r=self.agent('Создай задачу сделать отчёт','eva');self.assertEqual(code,200);self.assertEqual(r['task_title'],'Сделать отчёт');self.assertEqual(r['agent'],'leo')
  with closing(store.connect()) as c:self.assertEqual(before,c.execute('SELECT count(*) FROM objects').fetchone()[0])
 def test_arbitrary_action_rejected(self):
  with patch('providers.generate',return_value='{"agent":"eva","action":"run_shell","args":{"command":"erase"}}'):
   code,r=self.agent('сделай что-то');self.assertEqual(code,503);self.assertIn('неподдерживаемое',r['error'])
 def test_invalid_json_fails_explicitly(self):
  with patch('providers.generate',return_value='not JSON'):
   code,r=self.agent('привет');self.assertEqual(code,503);self.assertIn('формате',r['error'])
 def test_connection_check_uses_real_provider_path_without_leaking_key(self):
  with patch.dict(os.environ,{'FOCUS_DEFAULT_PROVIDER':'gemini','GEMINI_API_KEY':'super-secret-for-test','FOCUS_ALLOW_EXTERNAL':'1'}):
   with patch('providers.post',return_value={'candidates':[{'content':{'parts':[{'text':'OK'}]}}]}) as network:
    code,r=self.request('/focus/check',{'agent':'nick'},self.token);self.assertEqual(code,200);self.assertEqual(r['provider'],'gemini');self.assertNotIn('super-secret',json.dumps(r));network.assert_called_once()
   with patch('providers.post',side_effect=providers.ProviderError('Не удалось связаться с сервисом')):
    code,r=self.request('/focus/check',{'agent':'nick'},self.token);self.assertEqual(code,503);self.assertIn('связаться',r['error'])
 def test_dns_failure_is_explained_without_sensitive_details(self):
  import socket,urllib.error
  class Broken:
   def open(self,*a,**k):raise urllib.error.URLError(socket.gaierror('DNS lookup failed'))
  with patch('providers.urllib.request.build_opener',return_value=Broken()):
   with self.assertRaisesRegex(providers.ProviderError,'DNS'):providers.post('https://example.com',{}, {})
 def test_gemini_payload_and_key_header(self):
  with patch.dict(os.environ,{'FOCUS_ALLOW_EXTERNAL':'1','GEMINI_API_KEY':'dummy'}):
   with patch('providers.post',return_value={'candidates':[{'content':{'parts':[{'text':'Привет'}]}}]}) as post:
    self.assertEqual(providers.generate('gemini','Привет'),'Привет');self.assertIn('generativelanguage.googleapis.com',post.call_args.args[0]);self.assertEqual(post.call_args.args[1]['x-goog-api-key'],'dummy')
if __name__=='__main__':unittest.main()
