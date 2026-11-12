import os,sys,tempfile,threading,json,unittest,urllib.request,urllib.error
from unittest.mock import patch
sys.path.insert(0,os.path.dirname(os.path.dirname(__file__)))
import store,app,agents,providers
from contextlib import closing
from http.server import ThreadingHTTPServer

def call(method,path,data=None,token=None):
 headers={'Content-Type':'application/json'}
 if token:headers['Authorization']='Bearer '+token
 request=urllib.request.Request(f'http://127.0.0.1:{PORT}'+path,data=json.dumps(data,ensure_ascii=False).encode() if data is not None else None,headers=headers,method=method)
 try:
  with urllib.request.urlopen(request,timeout=5) as r:return r.status,json.load(r)
 except urllib.error.HTTPError as e:return e.code,json.load(e)
def login(user,password):
 code,body=call('POST','/auth/login',{'username':user,'password':password});assert code==200,body;return body['token']
class TestAPI(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  global PORT
  cls.tmp=tempfile.TemporaryDirectory();store.DB_PATH=os.path.join(cls.tmp.name,'test.sqlite3');store.seed()
  cls.server=ThreadingHTTPServer(('127.0.0.1',0),app.Handler);PORT=cls.server.server_port
  cls.thread=threading.Thread(target=cls.server.serve_forever,daemon=True);cls.thread.start()
  cls.d=login('director','Director-demo-2026!');cls.e=login('employee','Employee-demo-2026!');cls.a=login('admin','Admin-demo-2026!');cls.m=login('manager','Manager-demo-2026!')
 @classmethod
 def tearDownClass(cls):cls.server.shutdown();cls.server.server_close();cls.tmp.cleanup()
 def test_web_assets_are_available_and_private_files_not_served(self):
  for path,expected in [('/', 'text/html'),('/style.css','text/css'),('/app.js','text/javascript'),('/assets/eva-avatar.png','image/png'),('/assets/team.png','image/png'),('/assets/intro-eva.mp4','video/mp4'),('/assets/intro-nick.mp4','video/mp4'),('/assets/intro-leo.mp4','video/mp4'),('/assets/intro-robby.mp4','video/mp4')]:
   with urllib.request.urlopen(f'http://127.0.0.1:{PORT}'+path,timeout=5) as response:
    self.assertEqual(response.status,200);self.assertTrue(response.headers['Content-Type'].startswith(expected));self.assertGreater(len(response.read()),100)
  self.assertEqual(call('GET','/data/app.sqlite3')[0],401)
 def test_01_agents_and_routing(self):
  code,body=call('GET','/agents',token=self.d);self.assertEqual(code,200);self.assertEqual(set(body['agents']),{'eva','leo','nick','robby'});self.assertEqual(body['agents']['leo']['character'],'кот')
  self.assertEqual(agents.route('Подготовь повестку встречи')[0],'nick');self.assertEqual(agents.route('Как дела?')[0],None);self.assertEqual(agents.route('Привет','eva')[0],'eva')
 def test_02_rights_and_no_leak(self):
  self.assertEqual(call('GET','/objects',token=None)[0],401)
  code,data=call('GET','/objects?kind=document',token=self.e);self.assertEqual(code,200);self.assertTrue(all(x['owner_id']==4 for x in data['objects']))
  with closing(store.connect()) as c:hidden=c.execute("SELECT id FROM objects WHERE department='Продажи' AND kind='document' LIMIT 1").fetchone()[0]
  code,body=call('GET',f'/objects/{hidden}',token=self.e);self.assertEqual(code,404);self.assertNotIn('Тестовый документ',json.dumps(body,ensure_ascii=False))
  self.assertEqual(call('GET','/objects',token=self.a)[1]['objects'],[])
 def test_03_preview_cancel_and_idempotency(self):
  payload={'kind':'task','title':'Тест задачи','department':'Производство','owner_id':4,'visibility':'department','data':{'status':'open','due':'2030-01-01T12:00:00+00:00'}}
  request={'kind':'create_object','idempotency_key':'unique-test-001','payload':payload}
  code,r=call('POST','/proposals',request,self.m);self.assertEqual(code,201);pid=r['proposal_id']
  before=call('GET','/objects?kind=task',token=self.m)[1]['objects'];self.assertFalse(any(x['title']=='Тест задачи' for x in before))
  self.assertEqual(call('POST',f'/proposals/{pid}/cancel',{},self.m)[1]['state'],'cancelled')
  self.assertEqual(call('POST',f'/proposals/{pid}/confirm',{},self.m)[0],409)
  request['idempotency_key']='unique-test-002';pid=call('POST','/proposals',request,self.m)[1]['proposal_id']
  a=call('POST',f'/proposals/{pid}/confirm',{},self.m)[1];b=call('POST',f'/proposals/{pid}/confirm',{},self.m)[1]
  self.assertEqual(a['result']['id'],b['result']['id']);self.assertTrue(b['replayed'])
  same=call('POST','/proposals',request,self.m)[1];self.assertEqual(same['state'],'confirmed')
 def test_04_mock_outbox_only_after_confirm(self):
  data={'kind':'send_message','idempotency_key':'send-test-001','payload':{'recipient':'example@example.test','title':'Тема','body':'Тестовое сообщение'}}
  pid=call('POST','/proposals',data,self.d)[1]['proposal_id'];self.assertEqual(call('GET','/test-outbox',token=self.d)[1]['messages'],[])
  result=call('POST',f'/proposals/{pid}/confirm',{},self.d)[1];self.assertEqual(result['result']['status'],'recorded_in_test_gateway')
  call('POST',f'/proposals/{pid}/confirm',{},self.d);self.assertEqual(len(call('GET','/test-outbox',token=self.d)[1]['messages']),1)
 def test_05_notifications_are_deduplicated(self):
  self.assertGreaterEqual(call('POST','/notifications/check',{},self.m)[1]['new_notifications'],1);self.assertEqual(call('POST','/notifications/check',{},self.m)[1]['new_notifications'],0)
 def test_06_ai_data_scope_and_no_execution(self):
  with closing(store.connect()) as c:
   doc=c.execute("SELECT id FROM objects WHERE title='Проверка вредоносного текста'").fetchone()[0]
   forbidden=c.execute("SELECT id FROM objects WHERE department='Продажи' AND kind='document' LIMIT 1").fetchone()[0]
  with patch('providers.generate',return_value='Черновик ответа') as model:
   code,r=call('POST','/focus/chat',{'text':'Кратко разберись с документом','agent':'robby','source_ids':[doc]},self.e)
   self.assertEqual(code,200);self.assertEqual(r['agent'],'robby');self.assertEqual(r['status'],'draft');self.assertEqual(model.call_count,1)
   self.assertEqual(call('POST','/focus/chat',{'text':'Проверь документ','agent':'robby','source_ids':[forbidden]},self.e)[0],404)
   self.assertEqual(model.call_count,1)
  self.assertEqual(call('GET','/test-outbox',token=self.e)[1]['messages'],[])
 def test_07_meeting_analysis(self):
  with closing(store.connect()) as c:tr=c.execute("SELECT id FROM objects WHERE kind='transcript' LIMIT 1").fetchone()[0]
  model='{"summary":"Обсуждение", "items":[{"type":"решено","text":"Сделать отчёт"}], "tasks":[{"text":"Отчёт","owner":"требует уточнения","due":"требует уточнения","basis":"подготовить отчёт"}]}'
  with patch('providers.generate',return_value=model):
   code,r=call('POST','/focus/analyze-meeting',{'transcript_id':tr},self.m);self.assertEqual(code,200);self.assertEqual(r['agent'],'nick');self.assertEqual(r['status'],'draft')
 def test_08_calendar_and_stop(self):
  query={'start':'2031-02-01T10:00:00+00:00','end':'2031-02-01T11:00:00+00:00','participants':[4],'duration_minutes':30}
  self.assertEqual(len(call('POST','/calendar/free',query,self.m)[1]['slots']),2)
  self.assertEqual(call('POST','/admin/stop',{'stopped':True},self.a)[0],200)
  with patch('providers.generate') as gen:self.assertEqual(call('POST','/focus/chat',{'text':'задачи','agent':'leo'},self.m)[0],409);gen.assert_not_called()
  self.assertEqual(call('POST','/admin/stop',{'stopped':False},self.a)[0],200)
 def test_09_audit_and_provider_gates(self):
  code,body=call('GET','/admin/audit',token=self.a);self.assertEqual(code,200);self.assertTrue(body['integrity']);self.assertTrue(any(x['result']=='denied' for x in body['events']))
  with patch.dict(os.environ,{'EXTERNAL_DEMO_ONLY':'0'}):
   with self.assertRaises(providers.ProviderError):providers.generate('openai','hello')
 def test_10_file_permission_lifecycle(self):
  from pathlib import Path
  file=Path(self.tmp.name)/'permission_test.txt';file.write_text('Демонстрационный текст документа.',encoding='utf-8')
  proposal={'kind':'grant_file','idempotency_key':'file-test-001','payload':{'path':str(file)}}
  code,p=call('POST','/proposals',proposal,self.e);self.assertEqual(code,201);self.assertEqual(call('GET','/files/grants',token=self.e)[1]['files'],[])
  self.assertEqual(call('GET','/files/1/read',token=self.e)[0],404)
  code,r=call('POST',f"/proposals/{p['proposal_id']}/confirm",{},self.e);self.assertEqual(code,200);fid=r['result']['id']
  self.assertEqual(call('GET',f'/files/{fid}/read',token=self.e)[1]['text'],'Демонстрационный текст документа.')
  self.assertEqual(call('GET',f'/files/{fid}/read',token=self.m)[0],404)
  with patch('providers.generate',return_value='Проверенный черновик') as model:
   code,answer=call('POST','/focus/file-chat',{'agent':'robby','provider':'ollama','text':'Что в документе?','file_ids':[fid]},self.e)
   self.assertEqual(code,200);self.assertEqual(answer['agent'],'robby');self.assertIn('Демонстрационный текст',model.call_args.args[2])
   self.assertEqual(call('POST','/focus/file-chat',{'agent':'robby','provider':'openai','text':'Прочитай документ','file_ids':[fid]},self.e)[0],403)
   self.assertEqual(model.call_count,1)
  self.assertEqual(call('POST',f'/files/{fid}/revoke',{},self.e)[1]['status'],'revoked')
  self.assertEqual(call('GET',f'/files/{fid}/read',token=self.e)[0],404)
  with patch('providers.generate') as model:
   self.assertEqual(call('POST','/focus/file-chat',{'agent':'robby','provider':'ollama','text':'Прочитай документ','file_ids':[fid]},self.e)[0],404);model.assert_not_called()
 def test_11_cancel_file_grant(self):
  from pathlib import Path
  file=Path(self.tmp.name)/'cancelled.txt';file.write_text('не читать',encoding='utf-8')
  data={'kind':'grant_file','idempotency_key':'file-cancel-test','payload':{'path':str(file)}}
  proposal=call('POST','/proposals',data,self.e)[1]['proposal_id'];call('POST',f'/proposals/{proposal}/cancel',{},self.e)
  self.assertEqual(call('POST',f'/proposals/{proposal}/confirm',{},self.e)[0],409)
  self.assertFalse(any(x['path']==str(file) for x in call('GET','/files/grants',token=self.e)[1]['files']))
 def test_12_docx_and_replaced_file(self):
  from pathlib import Path
  import shutil
  source=Path(__file__).resolve().parents[1]/'test_files'/'documents'/'21_пример_word.docx'
  path=Path(self.tmp.name)/'example.docx';shutil.copyfile(source,path)
  data={'kind':'grant_file','idempotency_key':'file-docx-test','payload':{'path':str(path)}}
  proposal=call('POST','/proposals',data,self.e)[1]['proposal_id'];result=call('POST',f'/proposals/{proposal}/confirm',{},self.e)[1];fid=result['result']['id']
  code,body=call('GET',f'/files/{fid}/read',token=self.e);self.assertEqual(code,200);self.assertIn('Пример рабочего документа',body['text'])
  replacement=Path(self.tmp.name)/'replacement.docx';shutil.copyfile(source,replacement);os.replace(replacement,path)
  self.assertEqual(call('GET',f'/files/{fid}/read',token=self.e)[0],400)
 def test_13_symlink_and_formats(self):
  from pathlib import Path
  import local_files
  source=Path(self.tmp.name)/'linksource.txt';source.write_text('x',encoding='utf-8');link=Path(self.tmp.name)/'shortcut.txt'
  try:link.symlink_to(source)
  except (OSError,NotImplementedError):self.skipTest('Символические ссылки недоступны в этой системе')
  with self.assertRaises(local_files.FileAccessError):local_files.inspect_file(str(link))
  with self.assertRaises(local_files.FileAccessError):local_files.path_syntax(str(source.with_suffix('.exe')))
 def test_14_registration_and_login(self):
  good={'name':'  Мария   Иванова ','username':'  Maria.Ivanova ','password':'Strong-pass-2026'}
  code,r=call('POST','/auth/register',good);self.assertEqual(code,201,r);self.assertEqual(r['role'],'employee');self.assertEqual(r['name'],'Мария Иванова')
  code,me=call('GET','/me',token=r['token']);self.assertEqual(code,200);self.assertEqual(me['role'],'employee')
  self.assertEqual(call('GET','/objects?kind=task',token=r['token'])[0],200)
  self.assertEqual(call('GET','/admin/audit',token=r['token'])[0],403)
  # повторный вход: логин не зависит от регистра и пробелов, пароль хранится только как хеш
  self.assertEqual(call('POST','/auth/login',{'username':' MARIA.ivanova','password':good['password']})[0],200)
  self.assertEqual(call('POST','/auth/login',{'username':'maria.ivanova','password':'wrong-password-1'})[0],401)
  with closing(store.connect()) as c:
   stored=c.execute("SELECT password,role FROM users WHERE username='maria.ivanova'").fetchone()
  self.assertTrue(stored['password'].startswith('pbkdf2_sha256$'));self.assertNotIn(good['password'],stored['password']);self.assertEqual(stored['role'],'employee')
  # занятый логин (в том числе другой регистр), слабые и некорректные данные
  self.assertEqual(call('POST','/auth/register',dict(good,username='MARIA.IVANOVA'))[0],409)
  self.assertEqual(call('POST','/auth/register',{'name':'Тест','username':'admin','password':'Strong-pass-2026'})[0],409)
  for bad in ({'name':'Т','username':'newuser','password':'Strong-pass-2026'},
              {'name':'Тест','username':'ab','password':'Strong-pass-2026'},
              {'name':'Тест','username':'bad name!','password':'Strong-pass-2026'},
              {'name':'Тест','username':'newuser','password':'short7!'},
              {'name':'Тест','username':'newuser','password':'12345678'},
              {'name':'Тест','username':'newuser12','password':'newuser12'},
              {'name':'','username':'newuser','password':'Strong-pass-2026'}):
   self.assertEqual(call('POST','/auth/register',bad)[0],400,bad)
  with closing(store.connect()) as c:
   self.assertIsNone(c.execute("SELECT 1 FROM users WHERE username IN ('newuser','ab','newuser12')").fetchone())
  # демо-вход прежних учётных записей не затронут
  self.assertEqual(call('POST','/auth/login',{'username':'arina','password':'1234'})[0],200)
 def test_15_document_folders_create_import_and_scope(self):
  from pathlib import Path
  code,created=call('POST','/folders',{'name':'Проекты'},self.e);self.assertEqual(code,201)
  folder_id=created['folder']['id']
  self.assertEqual(call('POST','/folders',{'name':'проекты'},self.e)[0],409)
  code,doc=call('POST','/documents',{'title':'План запуска','text':'Содержимое плана.','folder_id':folder_id,'format':'md'},self.e);self.assertEqual(code,201)
  self.assertEqual(doc['folder_id'],folder_id)
  listing=call('GET',f'/documents/library?folder_id={folder_id}',token=self.e)[1]['documents']
  self.assertEqual([x['title'] for x in listing],['План запуска'])
  self.assertEqual(call('GET',f'/documents/library?folder_id={folder_id}',token=self.m)[0],404)
  self.assertEqual(call('GET','/folders',token=self.m)[1]['folders'],[])
  source=Path(self.tmp.name)/'imported.txt';source.write_text('Текст для импорта.',encoding='utf-8')
  code,imported=call('POST','/documents/import',{'path':source.as_uri(),'folder_id':folder_id},self.e)
  self.assertEqual(code,201);self.assertEqual(imported['original_name'],'imported.txt')
  self.assertEqual(call('GET',f"/objects/{imported['id']}",token=self.e)[1]['object']['data']['text'],'Текст для импорта.')
  bad=Path(self.tmp.name)/'blocked.exe';bad.write_text('не поддерживается',encoding='utf-8')
  self.assertEqual(call('POST','/documents/import',{'path':str(bad)},self.e)[0],400)
  self.assertEqual(call('POST','/folders',{'name':'Admin folder'},self.a)[0],403)
 def test_16_directory_security_and_encrypted_document(self):
  import sqlite3
  people=call('GET','/directory',token=self.e)[1]['people']
  self.assertEqual([x['id'] for x in people],[4])
  self.assertTrue(all(x['department']=='Производство' for x in call('GET','/directory',token=self.m)[1]['people']))
  status=call('GET','/security/status',token=self.e)[1]
  self.assertTrue(status['audit_integrity']);self.assertFalse(status['audit_access']);self.assertIn('DPAPI',status['storage'])
  self.assertEqual(call('GET','/security/status')[0],401)
  code,doc=call('POST','/documents',{'title':'Storage check','text':'PRIVATE-API-DOCUMENT-SENTINEL'},self.e)
  self.assertEqual(code,201)
  with closing(sqlite3.connect(store.DB_PATH)) as raw:
   ciphertext=raw.execute('SELECT data FROM objects WHERE id=?',(doc['id'],)).fetchone()[0]
  self.assertTrue(ciphertext.startswith('focus-dpapi-v1:'));self.assertNotIn('PRIVATE-API-DOCUMENT-SENTINEL',ciphertext)
  self.assertEqual(call('GET',f"/objects/{doc['id']}",token=self.e)[1]['object']['data']['text'],'PRIVATE-API-DOCUMENT-SENTINEL')
 def test_17_workspace_state_is_scoped_encrypted_and_persistent(self):
  import sqlite3
  code,state=call('GET','/workspace/tasks',token=self.e);self.assertEqual(code,200)
  self.assertTrue(state['tasks']);self.assertTrue(state['mail']);self.assertIn('trend',state)
  self.assertEqual(call('POST','/workspace/action',{'action':'move_demo_task','id':'demo-t1','status':'done'},self.e)[0],200)
  changed=call('GET','/workspace/tasks',token=self.e)[1]
  self.assertEqual(next(x for x in changed['tasks'] if x['id']=='demo-t1')['status'],'done')
  other=call('GET','/workspace/tasks',token=self.m)[1]
  self.assertEqual(next(x for x in other['tasks'] if x['id']=='demo-t1')['status'],'open')
  with closing(sqlite3.connect(store.DB_PATH)) as raw:
   value=raw.execute('SELECT payload FROM workspace_state WHERE user_id=4').fetchone()[0]
  self.assertTrue(value.startswith('focus-dpapi-v1:'));self.assertNotIn('Орбита',value)
  self.assertEqual(call('GET','/workspace/tasks')[0],401)
  self.assertEqual(call('GET','/workspace/unknown',token=self.e)[0],404)
  self.assertEqual(call('POST','/workspace/action',{'action':'recent','id':999999},self.e)[0],400)
 def test_18_workspace_chat_history_and_exports(self):
  import base64,io,zipfile
  plan=json.dumps({'agent':'eva','action':'answer','args':{},'answer':'Здравствуйте, помогу с рабочими задачами.'},ensure_ascii=False)
  with patch('providers.generate',return_value=plan):
   self.assertEqual(call('POST','/focus/agent',{'agent':'eva','text':'Здравствуйте','history':[]},self.e)[0],200)
  history=call('GET','/workspace/chat',token=self.e)[1]['chat']
  self.assertEqual(history[-1]['text'],'Здравствуйте, помогу с рабочими задачами.')
  self.assertEqual(call('GET','/workspace/chat',token=self.m)[1]['chat'],[])
  code,result=call('POST','/workspace/export',{'title':'Отчёт','rows':[{'title':'=1+1','detail':'Текст отчёта'}]},self.e)
  self.assertEqual(code,200)
  with zipfile.ZipFile(io.BytesIO(base64.b64decode(result['content']))) as z:
   sheet=z.read('xl/worksheets/sheet1.xml').decode()
   self.assertIn('Текст отчёта',sheet);self.assertNotIn('<f>',sheet)
 def test_19_role_change_requires_admin_confirmation_request(self):
  self.assertEqual(call('POST','/admin/users/4/role',{'role':'director'},self.e)[0],403)
  self.assertEqual(call('POST','/admin/users/1/role',{'role':'employee'},self.a)[0],400)
  created=call('POST','/admin/users',{'name':'Новый сотрудник','username':'role.case','department':'IT','role':'employee','password':'Role-change-2026!'},self.a)
  self.assertEqual(created[0],201)
  self.assertEqual(call('POST',f"/admin/users/{created[1]['id']}/role",{'role':'manager'},self.a)[0],200)
  self.assertEqual(call('POST','/auth/login',{'username':'role.case','password':'Role-change-2026!'})[1]['role'],'manager')
if __name__=='__main__':unittest.main(verbosity=2)
