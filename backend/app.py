#!/usr/bin/env python3
"""Focus: local HTTP/JSON backend prototype. No framework dependencies."""
import os,json,re,sys,secrets,datetime,hashlib,sqlite3,threading,time
from pathlib import Path
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from urllib.parse import urlparse,parse_qs,unquote
from contextlib import closing
import store,security,providers,agents,local_files,agent_runtime,workspace,media_upload

KINDS={'document','transcript','task','meeting','protocol','approval','decision','time_record'}
class APIError(Exception):
 def __init__(self,status,message):self.status=status;self.message=message

def require(cond,msg='Недостаточно прав',status=403):
 if not cond:raise APIError(status,msg)
def iso_date(value):
 if not isinstance(value,str):raise APIError(400,'Требуется дата и время с часовым поясом')
 try:
  dt=datetime.datetime.fromisoformat(value.replace('Z','+00:00'))
  if dt.tzinfo is None:raise ValueError()
  return dt.astimezone(datetime.timezone.utc)
 except ValueError:raise APIError(400,'Дата и время должны содержать часовой пояс')
def parse_json(x):
 try:return json.loads(x)
 except (ValueError,TypeError):return {}
def obj(row):
 out=dict(row);out['data']=parse_json(out['data']);return out

def can_view(u,r):
 if not r or r['company']!=u['company'] or u['role']=='admin':return False
 if u['role']=='director':return True
 if r['owner_id']==u['id']:return True
 if r['visibility']=='company':return True
 if u['role']=='manager' and r['department']==u['department'] and r['visibility']=='department':return True
 return False

def get_object(c,u,oid):
 row=c.execute('SELECT * FROM objects WHERE id=?',(oid,)).fetchone()
 if not can_view(u,row):
  store.audit(c,u['id'],'access',oid,'denied','Объект недоступен')
  c.commit();raise APIError(404,'Объект не найден или недоступен')
 return row

def allowed_write(u,row):
 if not can_view(u,row):return False
 return u['role']=='director' or (u['role']=='manager' and row['department']==u['department']) or row['owner_id']==u['id']

USERNAME_RE=re.compile(r'[a-z0-9._-]{3,32}')
WEAK_PASSWORDS={'12345678','123456789','1234567890','password','password1','qwerty123','qwertyui','11111111','00000000','йцукенгш'}
# Защита от подбора пароля: не более LOGIN_MAX неудачных попыток на логин за LOGIN_WINDOW секунд.
LOGIN_MAX=8;LOGIN_WINDOW=300;_fails={};_fails_lock=threading.Lock()
_DUMMY_HASH=security.hash_password('dummy-password-for-timing',8)
def login_locked(name):
 with _fails_lock:
  now=time.monotonic();recent=[t for t in _fails.get(name,()) if now-t<LOGIN_WINDOW]
  if recent:_fails[name]=recent
  else:_fails.pop(name,None)
  return len(recent)>=LOGIN_MAX
def login_failed(name):
 with _fails_lock:
  if len(_fails)>5000:_fails.clear()
  _fails.setdefault(name,[]).append(time.monotonic())
def login_ok(name):
 with _fails_lock:_fails.pop(name,None)
def open_session(c,user):
 c.execute('DELETE FROM sessions WHERE expires<=?',(store.now(),))
 token=security.new_token();expires=(datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(hours=8)).isoformat(timespec='seconds')
 c.execute('INSERT INTO sessions VALUES (?,?,?)',(security.token_hash(token),user['id'],expires));store.audit(c,user['id'],'login');c.commit()
 return {'token':token,'expires':expires,'role':user['role'],'name':user['name']}
def register_user(c,b):
 # Самостоятельная регистрация всегда создаёт сотрудника без особых прав.
 name=' '.join(str(b.get('name','')).split());username=str(b.get('username','')).strip().lower();password=str(b.get('password',''))
 require(2<=len(name)<=60,'Имя должно содержать от 2 до 60 символов',400)
 require(USERNAME_RE.fullmatch(username) is not None,'Логин: 3–32 символа — латиница, цифры, точка, дефис или подчёркивание',400)
 require(len(password)>=8,'Пароль должен содержать не менее 8 символов',400)
 require(len(password)<=200,'Пароль не должен быть длиннее 200 символов',400)
 require(password.lower()!=username and password.lower() not in WEAK_PASSWORDS,'Этот пароль слишком простой — придумайте другой',400)
 try:cur=c.execute('INSERT INTO users(company,username,name,password,role,department) VALUES (?,?,?,?,?,?)',('demo',username,name,security.hash_password(password,8),'employee','Общий'))
 except store.sqlite3.IntegrityError:raise APIError(409,'Этот логин уже занят')
 user=c.execute('SELECT * FROM users WHERE id=?',(cur.lastrowid,)).fetchone();store.audit(c,user['id'],'register');return user

def auth(c,header):
 if not header.startswith('Bearer '):raise APIError(401,'Войдите в систему')
 row=c.execute('SELECT u.* FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token_hash=? AND s.expires>? AND u.active=1',(security.token_hash(header[7:]),store.now())).fetchone()
 if not row:raise APIError(401,'Сессия недействительна или истекла')
 return row

def selected_provider(agent,request):
 value=request.get('provider') or os.getenv('FOCUS_AGENT_'+agent.upper()+'_PROVIDER',os.getenv('FOCUS_DEFAULT_PROVIDER','ollama'))
 require(isinstance(value,str) and value.lower() in ('ollama','openai','anthropic','gemini'),'Допустимые провайдеры: ollama, openai, anthropic, gemini',400)
 return value.lower()

def valid_payload(c,u,kind,payload):
 require(isinstance(payload,dict),'Поле payload должно быть объектом',400)
 if kind=='grant_file':
  require(u['role']!='admin')
  try:local_files.path_syntax(payload.get('path'))
  except local_files.FileAccessError as e:raise APIError(400,str(e))
  require(set(payload)=={'path'},'Укажите только путь к файлу',400)
  return
 if kind=='send_message':
  require(u['role'] in ('director','manager','employee'),'Недостаточно прав')
  for k in ('recipient','title','body'):require(isinstance(payload.get(k),str) and 0<len(payload[k])<=5000,f'Проверьте поле {k}',400)
  if payload.get('source_id') is not None:get_object(c,u,int(payload['source_id']))
  return
 if kind=='update_object':
  row=get_object(c,u,int(payload.get('id',0)));require(allowed_write(u,row))
  require(type(payload.get('version')) is int and payload['version']==row['version'],'Версия изменилась. Подготовьте новое предложение',409)
  require(isinstance(payload.get('data'),dict),'data должна быть объектом',400)
  if row['kind']=='approval':
   raise APIError(409,'Изменение согласований пока не реализовано; решение согласующего не подменяется')
  return
 require(kind=='create_object','Неизвестный тип действия',400)
 require(u['role']!='admin')
 typ=payload.get('kind'); require(typ in KINDS,'Недопустимый тип объекта',400)
 title=payload.get('title');require(isinstance(title,str) and 0<len(title.strip())<=250,'Укажите название до 250 символов',400)
 require(isinstance(payload.get('data',{}),dict),'data должна быть объектом',400)
 dep=payload.get('department') or u['department'];require(isinstance(dep,str) and 0<len(dep)<=100,'Некорректное подразделение',400)
 require(u['role']=='director' or dep==u['department'])
 visibility=payload.get('visibility','private');require(visibility in ('private','department','company'),'Недопустимая область доступа',400)
 if visibility=='company':require(u['role']=='director','Доступ всей компании назначает руководитель')
 owner_id=payload.get('owner_id',u['id']);require(type(owner_id) is int,'Некорректный владелец',400)
 target=c.execute('SELECT * FROM users WHERE id=? AND company=? AND active=1',(owner_id,u['company'])).fetchone();require(target is not None,'Сотрудник не найден',400)
 require(u['role']=='director' or (u['role']=='manager' and target['department']==u['department']) or owner_id==u['id'])
 if payload.get('source_id') is not None:get_object(c,u,int(payload['source_id']))
 data=payload.get('data',{})
 if typ=='task' and data.get('due'):iso_date(data['due'])
 if typ=='meeting':
  start=iso_date(data.get('start'));end=iso_date(data.get('end'));require(end>start,'Конец встречи должен быть позже начала',400)
  participants=data.get('participants',[owner_id]);require(isinstance(participants,list) and len(participants)<=30 and all(type(x) is int for x in participants),'Некорректные участники',400)
  for pid in participants:
   target=c.execute('SELECT * FROM users WHERE id=? AND company=? AND active=1',(pid,u['company'])).fetchone();require(target is not None,'Участник не найден',400)
   require(u['role']=='director' or target['department']==u['department'],'Участник недоступен')
 if typ=='approval':
  doc=get_object(c,u,int(data.get('document_id',0)));require(doc['kind']=='document','Нужен документ',400)
  require(data.get('document_version')==doc['version'],'Версия документа изменилась',409)

def calendar_free(c,u,payload):
 if payload.get('kind')!='meeting':return
 d=payload.get('data',{});start,end=iso_date(d['start']),iso_date(d['end']); people=set(d.get('participants',[payload.get('owner_id',u['id'])]))
 for r in c.execute("SELECT * FROM objects WHERE company=? AND kind='meeting'",(u['company'],)):
  other=parse_json(r['data'])
  try:
   if people.intersection(other.get('participants',[r['owner_id']])) and start<iso_date(other['end']) and end>iso_date(other['start']):raise APIError(409,'Интервал занят; подробности закрытых встреч не раскрываются')
  except KeyError:continue

def execute(c,u,proposal):
 kind=proposal['kind'];payload=parse_json(proposal['payload']);valid_payload(c,u,kind,payload)
 if c.execute("SELECT value FROM settings WHERE key='stopped'").fetchone()[0]=='1':raise APIError(409,'Агент остановлен администратором')
 if kind=='grant_file':
  try:info=local_files.inspect_file(payload['path'])
  except local_files.FileAccessError as e:raise APIError(400,str(e))
  c.execute('INSERT INTO file_grants(company,user_id,path,name,extension,dev,ino,active,created) VALUES (?,?,?,?,?,?,?,?,?) ON CONFLICT(company,user_id,path) DO UPDATE SET name=excluded.name,extension=excluded.extension,dev=excluded.dev,ino=excluded.ino,active=1,created=excluded.created',(u['company'],u['id'],info['path'],info['name'],info['extension'],info['dev'],info['ino'],1,store.now()))
  grant=c.execute('SELECT id FROM file_grants WHERE company=? AND user_id=? AND path=?',(u['company'],u['id'],info['path'])).fetchone()
  return {'id':grant['id'],'status':'read_only_granted','file':info['name'],'warning':'Разрешено только чтение этого файла; агенты не получают доступ ко всему компьютеру'}
 if kind=='send_message':
  t=store.now();i=c.execute('INSERT INTO messages(company,user_id,direction,title,body,recipient,created,proposal_id) VALUES (?,?,?,?,?,?,?,?)',(u['company'],u['id'],'outbox_mock',payload['title'],store.seal(payload['body']),payload['recipient'],t,proposal['id'])).lastrowid
  return {'id':i,'status':'recorded_in_test_gateway','warning':'Это тестовый шлюз; реальное письмо не отправлено'}
 if kind=='update_object':
  row=get_object(c,u,payload['id']);new_data=payload['data'];t=store.now()
  c.execute('UPDATE objects SET data=?,version=version+1,updated=? WHERE id=? AND version=?',(store.seal(store.dump(new_data)),t,row['id'],row['version']))
  return {'id':row['id'],'version':row['version']+1,'status':'updated'}
 calendar_free(c,u,payload);t=store.now();data=payload.get('data',{})
 i=c.execute('INSERT INTO objects(company,kind,title,department,owner_id,visibility,data,source_id,created_by,created,updated) VALUES (?,?,?,?,?,?,?,?,?,?,?)',(u['company'],payload['kind'],payload['title'].strip(),payload.get('department') or u['department'],payload.get('owner_id',u['id']),payload.get('visibility','private'),store.seal(store.dump(data)),payload.get('source_id'),u['id'],t,t)).lastrowid
 return {'id':i,'version':1,'status':'created'}

def list_objects(c,u,kind=None):
 rows=c.execute('SELECT * FROM objects WHERE company=?'+(' AND kind=?' if kind else '')+' ORDER BY id',(u['company'],kind) if kind else (u['company'],)).fetchall()
 return [obj(r) for r in rows if can_view(u,r)]

def owned_folder(c,u,folder_id):
 if folder_id is None:return None
 require(type(folder_id) is int and folder_id>0,'Некорректная папка',400)
 row=c.execute('SELECT * FROM document_folders WHERE id=? AND company=? AND owner_id=?',(folder_id,u['company'],u['id'])).fetchone()
 require(row is not None,'Папка не найдена или недоступна',404)
 return row

def create_document(c,u,title,text,folder_id=None,extension='txt'):
 require(u['role']!='admin')
 require(isinstance(title,str) and 0<len(title.strip())<=250,'Укажите название до 250 символов',400)
 require(isinstance(text,str) and 0<len(text.strip())<=100000,'Добавьте текст документа до 100 000 символов',400)
 require(isinstance(extension,str) and extension.lower().lstrip('.') in ('txt','md','csv','json','docx','pdf'),'Формат документа не поддерживается',400)
 folder=owned_folder(c,u,folder_id)
 data={'text':text,'folder_id':folder['id'] if folder else None,'format':extension.lower().lstrip('.'),'original_name':title.strip()}
 t=store.now()
 oid=c.execute('INSERT INTO objects(company,kind,title,department,owner_id,visibility,data,source_id,created_by,created,updated) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
  (u['company'],'document',title.strip(),u['department'],u['id'],'private',store.seal(store.dump(data)),None,u['id'],t,t)).lastrowid
 store.audit(c,u['id'],'document.create',oid,'ok','Личный документ сохранён')
 c.commit()
 return {'id':oid,'title':title.strip(),'folder_id':folder['id'] if folder else None,'created':t}

def import_file_path(value):
 require(isinstance(value,str) and 0<len(value)<=4000,'Выберите один локальный файл',400)
 if value.startswith('file:'):
  parsed=urlparse(value)
  require(parsed.scheme=='file' and parsed.netloc in ('','localhost'),'Разрешены только локальные файлы',400)
  value=unquote(parsed.path)
  if os.name=='nt':
   if re.match(r'^/[A-Za-z]:/',value):value=value[1:]
   value=value.replace('/','\\')
 try:return local_files.path_syntax(value)
 except local_files.FileAccessError as e:raise APIError(400,str(e))

def overdue(item):
 try:return item['kind']=='task' and item['data'].get('status') not in ('завершена','отменена','done','cancelled') and bool(item['data'].get('due')) and iso_date(item['data']['due'])<datetime.datetime.now(datetime.timezone.utc)
 except APIError:return False

def dashboard(c,u):
 tasks=list_objects(c,u,'task');approvals=list_objects(c,u,'approval');meetings=list_objects(c,u,'meeting')
 open_tasks=[x for x in tasks if x['data'].get('status') not in ('завершена','отменена','done','cancelled')];no_owner=[x for x in open_tasks if not x['owner_id']]
 overdue_approvals=[]
 for x in approvals:
  try:
   if x['data'].get('status')=='на согласовании' and x['data'].get('due') and iso_date(x['data']['due'])<datetime.datetime.now(datetime.timezone.utc):overdue_approvals.append(x)
  except APIError:pass
 return {'updated_at':store.now(),'metrics':[{'id':'KPI-01','value':sum(overdue(x) for x in tasks),'unit':'шт.','formula':'срок ранее текущего времени и статус не завершена/отменена','source':'tasks'}, {'id':'KPI-02','value':round(len(no_owner)/len(open_tasks)*100,2) if open_tasks else None,'unit':'%','formula':'открытые задачи без владельца / все открытые задачи × 100','source':'tasks'}, {'id':'KPI-04','value':len(overdue_approvals),'unit':'шт.','formula':'согласования со статусом на согласовании и прошедшим сроком','source':'approvals'}], 'other_kpi':'Не реализованы; источники и правила нужно утвердить','links':{'tasks':[x['id'] for x in tasks if overdue(x)],'approvals':[x['id'] for x in overdue_approvals]}}

class Handler(BaseHTTPRequestHandler):
 server_version='FocusDev/0.1'
 def log_message(self,*a):pass
 def send(self,status,data):
  raw=json.dumps(data,ensure_ascii=False,default=str).encode();self.send_response(status);self.send_header('Content-Type','application/json; charset=utf-8');self.send_header('Content-Length',str(len(raw)));self.send_header('Cache-Control','no-store');self.send_header('X-Content-Type-Options','nosniff');self.end_headers();self.wfile.write(raw)
 def body(self):
  try:n=int(self.headers.get('Content-Length','0'))
  except ValueError:raise APIError(400,'Некорректный Content-Length')
  require(0<=n<=1_000_000,'Превышен размер запроса',413)
  try:result=json.loads(self.rfile.read(n).decode()) if n else {}
  except (ValueError,UnicodeError):raise APIError(400,'Некорректный JSON')
  require(isinstance(result,dict),'Ожидается JSON-объект',400);return result
 def do_GET(self):
  path=urlparse(self.path).path
  static={'/':('index.html','text/html; charset=utf-8'),'/app.js':('app.js','text/javascript; charset=utf-8'),'/style.css':('style.css','text/css; charset=utf-8')}
  if path.startswith('/assets/') and re.fullmatch(r'/assets/(?:eva|nick|leo|robby)(?:-avatar)?\.png|/assets/team\.png|/assets/logo\.jpg',path):
   static[path]=(path.lstrip('/'),'image/jpeg' if path.endswith('.jpg') else 'image/png')
  if re.fullmatch(r'/assets/intro-(?:eva|nick|robby|leo)\.mp4',path):
   static[path]=(path.lstrip('/'),'video/mp4')
  if path in static:
   name,mime=static[path];raw=(Path(__file__).parent/'web'/name).read_bytes()
   self.send_response(200);self.send_header('Content-Type',mime);self.send_header('Content-Length',str(len(raw)));self.send_header('Cache-Control','no-store');self.send_header('X-Content-Type-Options','nosniff');self.end_headers();self.wfile.write(raw);return
  self.handle_request('GET')
 def do_POST(self):self.handle_request('POST')
 def handle_request(self,method):
  try:
   p=urlparse(self.path);body=self.body() if method=='POST' else {};status,out=self.dispatch(method,p.path,parse_qs(p.query),body);self.send(status,out)
  except APIError as e:self.send(e.status,{'error':e.message})
  except providers.ProviderError as e:self.send(503,{'error':str(e),'status':'provider_unavailable'})
  except (ValueError,TypeError,KeyError) as e:self.send(400,{'error':'Некорректные параметры запроса'})
  except Exception as e:
   print('Request error:',type(e).__name__,file=sys.stderr);self.send(500,{'error':'Внутренняя ошибка; действие не подтверждено'})
 def dispatch(self,method,path,q,b):
  with closing(store.connect()) as c:
   if method=='GET' and path=='/health':return 200,{'status':'ok','mode':'local_demo','frontend':True}
   if method=='POST' and path=='/auth/login':
    name=str(b.get('username','')).strip().lower()[:100];password=str(b.get('password',''))[:200]
    if login_locked(name):raise APIError(429,'Слишком много неудачных попыток входа. Подождите несколько минут')
    user=c.execute('SELECT * FROM users WHERE username=?',(name,)).fetchone()
    # проверка пароля выполняется всегда, чтобы по времени ответа нельзя было узнать, существует ли логин
    pw_ok=security.check_password(password,user['password'] if user else _DUMMY_HASH)
    if not user or not user['active'] or not pw_ok:
     login_failed(name);store.audit(c,user['id'] if user else None,'login','', 'denied','Неверные учётные данные');c.commit();raise APIError(401,'Неверное имя или пароль')
    login_ok(name);return 200,open_session(c,user)
   if method=='POST' and path=='/auth/register':
    user=register_user(c,b);c.commit();return 201,open_session(c,user)
   u=auth(c,self.headers.get('Authorization',''))
   if method=='GET' and path.startswith('/workspace/'):
    section=path.rsplit('/',1)[-1];require(section in workspace.SECTIONS,'Раздел не найден',404)
    objects={kind:list_objects(c,u,kind) for kind in ('task','document','meeting')}
    return 200,workspace.snapshot(c,u,section,objects)
   if method=='POST' and path=='/media/transcribe':
    require(u['role']!='admin');text=media_upload.transcribe(b.get('path'))
    workspace.action(c,u,{'action':'transcript','text':text},set())
    return 200,{'text':text}
   if method=='POST' and path=='/workspace/action':
    ids={x['id'] for x in list_objects(c,u,'document')}
    try:return 200,workspace.action(c,u,b,ids)
    except ValueError as exc:raise APIError(400,str(exc))
   if method=='POST' and path=='/workspace/export':
    return 200,workspace.spreadsheet(b.get('rows'),str(b.get('title','Отчёт Focus'))[:200])
   if method=='POST' and path=='/workspace/ai':
    require(u['role']!='admin')
    question=b.get('question');context=b.get('context','')
    require(isinstance(question,str) and 0<len(question)<=12000 and isinstance(context,str) and len(context)<=24000,'Некорректный запрос',400)
    provider=selected_provider('robby',{})
    minute=datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M')
    c.execute('INSERT OR IGNORE INTO limits VALUES (?,?,0)',(u['id'],minute))
    count=c.execute('SELECT calls FROM limits WHERE user_id=? AND window=?',(u['id'],minute)).fetchone()[0]
    require(count<int(os.getenv('MODEL_CALLS_PER_MINUTE','30')),'Достигнут лимит запросов к модели',429)
    c.execute('UPDATE limits SET calls=calls+1 WHERE user_id=? AND window=?',(u['id'],minute));c.commit()
    language=workspace.load(c,u)['preferences'].get('language','Русский')
    answer=providers.generate(provider,question+'\nПредпочитаемый язык ответа: '+language,context)
    store.audit(c,u['id'],'workspace.ai','','ok','Получен черновик без автоматических действий');c.commit()
    return 200,{'answer':answer}
   if method=='POST' and path=='/auth/logout':
    c.execute('DELETE FROM sessions WHERE token_hash=?',(security.token_hash(self.headers.get('Authorization','')[7:]),));store.audit(c,u['id'],'logout');c.commit();return 200,{'status':'signed_out'}
   if method=='GET' and path=='/me':return 200,{'id':u['id'],'name':u['name'],'role':u['role'],'department':u['department'],'profile':parse_json(u['profile'])}
   if method=='POST' and path=='/me/profile':
    allowed=('display_name','position','department_label','responsibilities','team_size','assistant_tasks','response_style','time_zone','sound_enabled')
    profile={k:b[k] for k in allowed if k in b};require(len(store.dump(profile))<=10000,'Профиль слишком большой',400)
    c.execute('UPDATE users SET profile=? WHERE id=?',(store.seal(store.dump(profile)),u['id']));store.audit(c,u['id'],'profile.update',u['id']);c.commit();return 200,{'profile':profile,'permissions_changed':False}
   if method=='GET' and path=='/agents':return 200,{'brand':'Focus','agents':agents.AGENTS,'animation_assets':'не включены; требуется интерфейс'}
   if method=='POST' and path=='/focus/route':
    key,reason=agents.route(str(b.get('text','')),b.get('agent'));return 200,{'agent':key,'character':agents.AGENTS.get(key),'reason':reason,'confirmation_required_for_actions':True}
   if method=='GET' and path=='/objects':
    kind=q.get('kind',[None])[0];require(kind is None or kind in KINDS,'Неизвестный тип',400);return 200,{'objects':list_objects(c,u,kind)}
   match=re.fullmatch(r'/objects/(\d+)',path)
   if method=='GET' and match:return 200,{'object':obj(get_object(c,u,int(match[1])))}
   if method=='GET' and path=='/directory':
    rows=c.execute('SELECT id,name,role,department,active FROM users WHERE company=? ORDER BY department,name',(u['company'],)).fetchall()
    visible=[dict(r) for r in rows if u['role'] in ('admin','director') or (u['role']=='manager' and r['department']==u['department']) or r['id']==u['id']]
    return 200,{'people':visible}
   if method=='GET' and path=='/security/status':
    return 200,{'passwords':'PBKDF2-HMAC-SHA256, 600 000 итераций','storage':'DPAPI — тексты документов, профили, сообщения и предложения','scope':'Ключ текущей учётной записи Windows; метаданные SQLite не зашифрованы','audit_integrity':store.audit_verify(c),'audit_access':u['role']=='admin'}
   if method=='GET' and path=='/folders':
    require(u['role']!='admin')
    folders=[dict(r) for r in c.execute('SELECT id,name,created FROM document_folders WHERE company=? AND owner_id=? ORDER BY name COLLATE NOCASE,id',(u['company'],u['id']))]
    return 200,{'folders':folders}
   if method=='POST' and path=='/folders':
    require(u['role']!='admin')
    name=b.get('name')
    require(isinstance(name,str) and 0<len(name.strip())<=80,'Название папки должно содержать от 1 до 80 символов',400)
    try:
     i=c.execute('INSERT INTO document_folders(company,owner_id,name,name_key,created) VALUES (?,?,?,?,?)',(u['company'],u['id'],name.strip(),name.strip().casefold(),store.now())).lastrowid
    except sqlite3.IntegrityError as e:
     if 'UNIQUE constraint failed' in str(e):raise APIError(409,'Папка с таким названием уже существует')
     raise
    store.audit(c,u['id'],'folder.create',i,'ok','Создана папка документов');c.commit()
    return 201,{'folder':{'id':i,'name':name.strip()}}
   if method=='GET' and path=='/documents/library':
    require(u['role']!='admin')
    folder_value=q.get('folder_id',[None])[0]
    folder_id=None
    if folder_value not in (None,'','all'):
     try:folder_id=int(folder_value)
     except ValueError:raise APIError(400,'Некорректная папка',400)
     owned_folder(c,u,folder_id)
    documents=list_objects(c,u,'document')
    if folder_id is not None:documents=[x for x in documents if x['data'].get('folder_id')==folder_id]
    return 200,{'documents':documents,'folder_id':folder_id}
   if method=='POST' and path=='/documents':
    require(u['role']!='admin')
    folder_id=b.get('folder_id')
    if folder_id in ('',0):folder_id=None
    result=create_document(c,u,b.get('title'),b.get('text'),folder_id,b.get('format','txt'))
    return 201,result
   if method=='POST' and path=='/documents/import':
    require(u['role']!='admin')
    folder_id=b.get('folder_id')
    if folder_id in ('',0):folder_id=None
    owned_folder(c,u,folder_id)
    path_value=import_file_path(b.get('path'))
    try:info,text=local_files.read_path(path_value)
    except local_files.FileAccessError as e:raise APIError(400,str(e))
    title=b.get('title') or info['name']
    result=create_document(c,u,title,text,folder_id,info['extension'].lstrip('.'))
    result['original_name']=info['name']
    return 201,result
   if method=='POST' and path=='/proposals':
    key=str(b.get('idempotency_key',''));require(8<=len(key)<=128,'Нужен idempotency_key длиной 8–128 символов',400)
    kind=b.get('kind');payload=b.get('payload');encoded=store.dump(payload)
    prior=c.execute('SELECT * FROM proposals WHERE company=? AND actor_id=? AND request_key=?',(u['company'],u['id'],key)).fetchone()
    if prior:
     require(prior['kind']==kind and prior['payload']==encoded,'Ключ уже использован для другого предложения',409)
     return 200,{'proposal_id':prior['id'],'state':prior['state'],'preview':parse_json(prior['payload']),'result':parse_json(prior['result'])}
    valid_payload(c,u,kind,payload)
    i=c.execute('INSERT INTO proposals(company,actor_id,kind,payload,request_key,created) VALUES (?,?,?,?,?,?)',(u['company'],u['id'],kind,store.seal(encoded),key,store.now())).lastrowid
    store.audit(c,u['id'],'proposal.create',i,'ok',kind);c.commit();return 201,{'proposal_id':i,'state':'pending','preview':payload,'confirmation_required':True}
   match=re.fullmatch(r'/proposals/(\d+)/(confirm|cancel)',path)
   if method=='POST' and match:
    c.execute('BEGIN IMMEDIATE');row=c.execute('SELECT * FROM proposals WHERE id=? AND company=? AND actor_id=?',(int(match[1]),u['company'],u['id'])).fetchone();require(row is not None,'Предложение не найдено',404)
    if row['state']=='confirmed':
     require(match[2]=='confirm','Подтверждённую операцию нельзя отменить этим методом',409)
     return 200,{'state':'confirmed','result':parse_json(row['result']),'replayed':True}
    require(row['state']=='pending','Предложение уже отменено',409)
    if match[2]=='cancel':c.execute("UPDATE proposals SET state='cancelled' WHERE id=?",(row['id'],));store.audit(c,u['id'],'proposal.cancel',row['id']);c.commit();return 200,{'state':'cancelled'}
    result=execute(c,u,row);c.execute("UPDATE proposals SET state='confirmed',result=? WHERE id=?",(store.seal(store.dump(result)),row['id']));store.audit(c,u['id'],'proposal.confirm',row['id'],'ok',row['kind']);c.commit();return 200,{'state':'confirmed','result':result,'replayed':False}
   if method=='GET' and path=='/documents/search':
    text=q.get('q',[''])[0].strip().lower();require(1<=len(text)<=200,'Введите строку поиска',400)
    found=[]
    for x in list_objects(c,u,'document'):
     content=str(x['data'].get('text',''));index=content.lower().find(text)
     if index>=0 or text in x['title'].lower():found.append({'id':x['id'],'title':x['title'],'updated':x['updated'],'fragment':content[max(index-70,0):max(index,0)+180]})
    store.audit(c,u['id'],'document.search','','ok',f'found={len(found)}');c.commit();return 200,{'results':found,'status':'found' if found else 'not_found'}
   if method=='POST' and path=='/calendar/free':
    require(u['role']!='admin');start=iso_date(b.get('start'));end=iso_date(b.get('end'));duration=b.get('duration_minutes',30);people=b.get('participants',[u['id']])
    require(end>start and end-start<=datetime.timedelta(days=7),'Период должен быть не более 7 дней',400)
    require(type(duration) is int and 15<=duration<=240,'Длительность 15–240 минут',400)
    require(isinstance(people,list) and 0<len(people)<=30 and all(type(i) is int for i in people),'Некорректные участники',400)
    for pid in people:
     person=c.execute('SELECT * FROM users WHERE id=? AND company=? AND active=1',(pid,u['company'])).fetchone();require(person is not None,'Участник не найден',404)
     require(u['role']=='director' or (u['role']=='manager' and person['department']==u['department']) or pid==u['id'])
    busy=[]
    for row in c.execute("SELECT * FROM objects WHERE company=? AND kind='meeting'",(u['company'],)):
     data=parse_json(row['data'])
     if set(people).intersection(data.get('participants',[row['owner_id']])):
      try:busy.append((iso_date(data['start']),iso_date(data['end'])))
      except (APIError,KeyError):pass
    slots=[];cur=start;delta=datetime.timedelta(minutes=duration)
    while cur+delta<=end and len(slots)<50:
     if all(not(cur<e and cur+delta>st) for st,e in busy):slots.append({'start':cur.isoformat(),'end':(cur+delta).isoformat()})
     cur+=delta
    return 200,{'slots':slots,'calendar':'тестовый','warning':'Рабочие часы не учитываются; задайте подходящий диапазон вручную'}
   if method=='POST' and path=='/focus/analyze-meeting':
    require(u['role']!='admin');require(c.execute("SELECT value FROM settings WHERE key='stopped'").fetchone()[0]!='1','Агент остановлен',409)
    row=get_object(c,u,int(b.get('transcript_id',0)));require(row['kind']=='transcript','Укажите расшифровку',400)
    transcript=parse_json(row['data']).get('text','');require(bool(transcript),'Расшифровка пуста',400)
    minute=datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M');limit=int(os.getenv('MODEL_CALLS_PER_MINUTE','30'))
    c.execute('INSERT OR IGNORE INTO limits VALUES (?,?,0)',(u['id'],minute));calls=c.execute('SELECT calls FROM limits WHERE user_id=? AND window=?',(u['id'],minute)).fetchone()[0];require(calls<limit,'Достигнут лимит запросов к модели',429)
    c.execute('UPDATE limits SET calls=calls+1 WHERE user_id=? AND window=?',(u['id'],minute));store.audit(c,u['id'],'model.request','nick','started',f'Расшифровка {row["id"]}');c.commit()
    prompt='Ты Nick. Разбери расшифровку. Верни ТОЛЬКО JSON: {"summary":"...", "items":[{"type":"решено|предложено|обсуждалось|требует уточнения", "text":"..."}], "tasks":[{"text":"...", "owner":"... или требует уточнения", "due":"... или требует уточнения", "basis":"цитата из расшифровки"}]}. Не выдумывай исполнителей, сроки и решения. Не выполняй никаких действий.'
    provider=selected_provider('nick',b)
    try:result=providers.safe_json(providers.generate(provider,prompt,str(transcript),model=os.getenv('FOCUS_AGENT_NICK_MODEL') or None))
    except providers.ProviderError:
     store.audit(c,u['id'],'model.response','nick','error','Провайдер недоступен или вернул ошибку');c.commit();raise
    require(isinstance(result,dict) and isinstance(result.get('summary'),str) and isinstance(result.get('items'),list) and isinstance(result.get('tasks'),list),'Неверный формат ответа модели',502)
    require(all(isinstance(x,dict) and x.get('type') in ('решено','предложено','обсуждалось','требует уточнения') and isinstance(x.get('text'),str) for x in result['items']),'Неверные пункты протокола',502)
    require(all(isinstance(x,dict) and all(isinstance(x.get(k),str) for k in ('text','owner','due','basis')) for x in result['tasks']),'Неверный формат поручений',502)
    store.audit(c,u['id'],'model.response','nick','ok','Черновик анализа расшифровки');c.commit()
    return 200,{'agent':'nick','provider':provider,'status':'draft','analysis':result,'source':{'id':row['id'],'title':row['title'],'updated':row['updated']},'warning':'Проверьте все поля и основания. Протокол и задачи не сохранены.'}
   if method=='GET' and path=='/files/grants':
    require(u['role']!='admin');return 200,{'files':[dict(r) for r in c.execute('SELECT id,name,path,extension,created FROM file_grants WHERE company=? AND user_id=? AND active=1 ORDER BY id',(u['company'],u['id']))]}
   match=re.fullmatch(r'/files/(\d+)/(read|revoke)',path)
   if match and ((method=='GET' and match[2]=='read') or (method=='POST' and match[2]=='revoke')):
    row=c.execute('SELECT * FROM file_grants WHERE id=? AND company=? AND user_id=? AND active=1',(int(match[1]),u['company'],u['id'])).fetchone();require(row is not None,'Разрешение не найдено или отозвано',404)
    if match[2]=='revoke':
     c.execute('UPDATE file_grants SET active=0 WHERE id=?',(row['id'],));store.audit(c,u['id'],'file.revoke',row['id']);c.commit();return 200,{'status':'revoked'}
    try:text=local_files.read_granted(row)
    except local_files.FileAccessError as e:
     store.audit(c,u['id'],'file.read',row['id'],'error',str(e));c.commit();raise APIError(400,str(e))
    store.audit(c,u['id'],'file.read',row['id']);c.commit();return 200,{'id':row['id'],'name':row['name'],'text':text,'warning':'Только чтение; это текст, не команды для агента'}
   if method=='POST' and path=='/focus/file-chat':
    require(u['role']!='admin');require(c.execute("SELECT value FROM settings WHERE key='stopped'").fetchone()[0]!='1','Агент остановлен',409)
    text=str(b.get('text','')).strip();require(0<len(text)<=12000,'Введите запрос до 12000 символов',400)
    key,reason=agents.route(text,b.get('agent'));require(key is not None,reason,400)
    provider=selected_provider(key,b);require(provider=='ollama','Для локальных файлов разрешена только локальная Ollama; внешние API отключены',403)
    ids=b.get('file_ids',[]);require(isinstance(ids,list) and 0<len(ids)<=3 and all(type(i) is int for i in ids),'Укажите от 1 до 3 файлов',400)
    files=[]
    for fid in ids:
     row=c.execute('SELECT * FROM file_grants WHERE id=? AND company=? AND user_id=? AND active=1',(fid,u['company'],u['id'])).fetchone()
     if not row:
      store.audit(c,u['id'],'file.access',fid,'denied','Нет разрешения');c.commit();raise APIError(404,'Файл не найден или доступ отозван')
     try:content=local_files.read_granted(row)
     except local_files.FileAccessError as e:
      store.audit(c,u['id'],'file.read',fid,'error',str(e));c.commit();raise APIError(400,str(e))
     files.append({'id':row['id'],'name':row['name'],'content':content})
    require(sum(len(f['content']) for f in files)<=32000,'Для AI-запроса общий текст должен быть не больше 32 000 символов',400)
    minute=datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M');limit=int(os.getenv('MODEL_CALLS_PER_MINUTE','30'))
    c.execute('INSERT OR IGNORE INTO limits VALUES (?,?,0)',(u['id'],minute));calls=c.execute('SELECT calls FROM limits WHERE user_id=? AND window=?',(u['id'],minute)).fetchone()[0];require(calls<limit,'Достигнут лимит запросов к модели',429)
    c.execute('UPDATE limits SET calls=calls+1 WHERE user_id=? AND window=?',(u['id'],minute));store.audit(c,u['id'],'file.model.request',key,'started','Файлы: '+','.join(str(i) for i in ids));c.commit()
    context='\n\n'.join('ФАЙЛ '+str(f['id'])+' / '+f['name']+'\n'+f['content'] for f in files)
    try:answer=providers.generate(provider,'Агент '+agents.AGENTS[key]['name']+'. Запрос: '+text,context,model=os.getenv('FOCUS_AGENT_'+key.upper()+'_MODEL') or None)
    except providers.ProviderError:
     store.audit(c,u['id'],'file.model.response',key,'error','Локальная модель недоступна');c.commit();raise
    store.audit(c,u['id'],'file.model.response',key,'ok','Ответ получен, действий не выполнено');c.commit()
    return 200,{'agent':key,'route_reason':reason,'provider':provider,'status':'draft','answer':answer,'sources':[{'id':f['id'],'name':f['name']} for f in files],'warning':'Проверьте ответ по источнику: модель может ошибаться. Действий с файлом не выполнялось.'}
   if method=='GET' and path=='/dashboard':return 200,dashboard(c,u)
   if method=='POST' and path=='/notifications/check':
    require(u['role'] in ('director','manager'))
    count=0
    for x in list_objects(c,u,'task'):
     if overdue(x):
      key=f'{u["company"]}:{u["id"]}:overdue:{x["id"]}:{x["data"].get("due")}';cur=c.execute('INSERT OR IGNORE INTO notifications(company,user_id,object_id,kind,reason,dedup_key,created) VALUES (?,?,?,?,?,?,?)',(u['company'],u['id'],x['id'],'overdue','Срок задачи прошёл',key,store.now()));count+=cur.rowcount
    store.audit(c,u['id'],'notifications.check','','ok',f'created={count}');c.commit();return 200,{'new_notifications':count}
   if method=='GET' and path=='/notifications':return 200,{'notifications':[dict(r) for r in c.execute('SELECT id,object_id,kind,reason,is_read,created FROM notifications WHERE company=? AND user_id=? ORDER BY id DESC',(u['company'],u['id']))]}
   if method=='GET' and path=='/test-outbox':return 200,{'messages':[dict(r) for r in c.execute('SELECT id,title,body,recipient,created FROM messages WHERE company=? AND user_id=? AND direction=?',(u['company'],u['id'],'outbox_mock'))],'warning':'Имитация почты, сообщения не отправлены в реальный сервис'}
   if method=='POST' and path=='/focus/check':
    require(u['role']!='admin');require(c.execute("SELECT value FROM settings WHERE key='stopped'").fetchone()[0]!='1','Агент остановлен администратором',409)
    key=b.get('agent');require(isinstance(key,str) and key in agents.AGENTS,'Выберите агента',400)
    provider=selected_provider(key,b);model=os.getenv('FOCUS_AGENT_'+key.upper()+'_MODEL') or None
    answer=providers.generate(provider,'Ответь одним словом: OK. Это тест связи.',model=model)
    if not answer.strip():raise providers.ProviderError('Сервис ответил без текста. Проверьте доступ к модели и попробуйте снова.')
    store.audit(c,u['id'],'model.connection_check',key,'ok',provider);c.commit()
    return 200,{'provider':provider,'message':'Сервис ответил на тестовый запрос.'}
   if method=='POST' and path=='/focus/agent':
    require(u['role']!='admin');require(c.execute("SELECT value FROM settings WHERE key='stopped'").fetchone()[0]!='1','Агент остановлен администратором',409)
    text=b.get('text');require(isinstance(text,str) and 0<len(text.strip())<=12000,'Введите запрос до 12000 символов',400)
    key,reason=agents.route(text,b.get('agent'));require(key is not None,reason,400)
    history=b.get('history',[]);require(isinstance(history,list) and len(history)<=10,'История диалога слишком большая',400)
    minute=datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M');limit=int(os.getenv('MODEL_CALLS_PER_MINUTE','30'))
    c.execute('INSERT OR IGNORE INTO limits VALUES (?,?,0)',(u['id'],minute));n=c.execute('SELECT calls FROM limits WHERE user_id=? AND window=?',(u['id'],minute)).fetchone()[0];require(n<limit,'Достигнут лимит запросов к модели',429)
    c.execute('UPDATE limits SET calls=calls+1 WHERE user_id=? AND window=?',(u['id'],minute));store.audit(c,u['id'],'agent.request',key,'started','Запрос к модели');c.commit()
    def list_records(kind,my_only):
     rows=list_objects(c,u,kind)
     if my_only:
      rows=[r for r in rows if r['owner_id']==u['id'] or (kind=='meeting' and u['id'] in r['data'].get('participants',[]))]
     return [{'id':r['id'],'title':r['title'],'data':r['data'],'updated':r['updated']} for r in rows[:12]]
    def search_documents(query):
     q=query.casefold();found=[]
     for r in list_objects(c,u,'document'):
      content=str(r['data'].get('text',''));pos=content.casefold().find(q)
      if pos>=0 or q in r['title'].casefold():found.append({'id':r['id'],'title':r['title'],'fragment':content[max(pos-70,0):max(pos,0)+300],'updated':r['updated']})
      if len(found)>=12:break
     return found
    callbacks={'list_tasks':lambda mine:list_records('task',mine),'list_meetings':lambda mine:list_records('meeting',mine),'search_documents':search_documents}
    provider=selected_provider(key,b)
    try:out=agent_runtime.ask_model(provider,key,text.strip(),history,'Язык ответа: '+workspace.load(c,u)['preferences'].get('language','Русский'),callbacks)
    except providers.ProviderError:
     store.audit(c,u['id'],'agent.response',key,'error','Модель или инструмент недоступен');c.commit();raise
    store.audit(c,u['id'],'agent.response',out['agent'],'ok','План обработан; без автоматических изменений');c.commit();workspace.remember(c,u,text.strip(),out['answer'],out['agent']);out['provider']=provider
    return 200,out
   if method=='POST' and path=='/focus/chat':
    require(u['role']!='admin');require(c.execute("SELECT value FROM settings WHERE key='stopped'").fetchone()[0]!='1','Агент остановлен администратором',409)
    text=str(b.get('text','')).strip();require(0<len(text)<=12000,'Введите запрос до 12000 символов',400)
    key,reason=agents.route(text,b.get('agent'));require(key is not None,reason,400)
    ids=b.get('source_ids',[]);require(isinstance(ids,list) and len(ids)<=8 and all(type(i) is int for i in ids),'Можно указать до 8 источников',400)
    rows=[get_object(c,u,i) for i in ids];context='\n\n'.join('ИСТОЧНИК '+str(r['id'])+' / '+r['title']+' / '+r['updated']+'\n'+store.dump(parse_json(r['data'])) for r in rows)
    minute=datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M');limit=int(os.getenv('MODEL_CALLS_PER_MINUTE','30'))
    c.execute('INSERT OR IGNORE INTO limits VALUES (?,?,0)',(u['id'],minute));n=c.execute('SELECT calls FROM limits WHERE user_id=? AND window=?',(u['id'],minute)).fetchone()[0];require(n<limit,'Достигнут лимит запросов к модели',429)
    c.execute('UPDATE limits SET calls=calls+1 WHERE user_id=? AND window=?',(u['id'],minute));store.audit(c,u['id'],'model.request',key,'started','Источники: '+','.join(str(i) for i in ids));c.commit()
    provider=selected_provider(key,b)
    try:answer=providers.generate(provider,'Агент '+agents.AGENTS[key]['name']+'. Область: '+agents.AGENTS[key]['area']+'. Отвечай только по своей области. Если запрос явно относится к другой области, попроси выбрать подходящего агента. Запрос: '+text,context,model=os.getenv('FOCUS_AGENT_'+key.upper()+'_MODEL') or None)
    except providers.ProviderError:
     store.audit(c,u['id'],'model.response',key,'error','Провайдер недоступен или вернул ошибку');c.commit();raise
    store.audit(c,u['id'],'model.response',key,'ok','Ответ получен; действий не выполнялось');c.commit()
    return 200,{'agent':key,'route_reason':reason,'provider':provider,'answer':answer,'status':'draft','sources':[{'id':r['id'],'title':r['title'],'updated':r['updated']} for r in rows],'warning':'Ответ модели необходимо проверить по источникам. Действий не выполнено.'}
   if method=='GET' and path=='/admin/users':
    require(u['role']=='admin');return 200,{'users':[dict(r) for r in c.execute('SELECT id,username,name,role,department,active FROM users WHERE company=? ORDER BY id',(u['company'],))]}
   if method=='POST' and path=='/admin/users':
    require(u['role']=='admin');name=b.get('name');username=b.get('username');department=b.get('department');role=b.get('role');password=b.get('password')
    require(all(isinstance(x,str) and 0<len(x)<=100 for x in (name,username,department)),'Заполните имя, логин и подразделение',400);require(role in ('admin','director','manager','employee'),'Недопустимая роль',400)
    require(isinstance(password,str),'Нужен пароль',400)
    try:hashed=security.hash_password(password)
    except ValueError as e:raise APIError(400,str(e))
    if c.execute('SELECT 1 FROM users WHERE username=?',(username,)).fetchone():raise APIError(409,'Логин уже существует')
    i=c.execute('INSERT INTO users(company,username,name,password,role,department) VALUES (?,?,?,?,?,?)',(u['company'],username,name,hashed,role,department)).lastrowid;store.audit(c,u['id'],'user.create',i,'ok',role);c.commit();return 201,{'id':i,'role':role}
   match=re.fullmatch(r'/admin/users/(\d+)/active',path)
   if method=='POST' and match:
    require(u['role']=='admin');uid=int(match[1]);require(uid!=u['id'],'Нельзя заблокировать собственный аккаунт',400);require(type(b.get('active')) is bool,'Нужен active: true или false',400)
    row=c.execute('SELECT id FROM users WHERE id=? AND company=?',(uid,u['company'])).fetchone();require(row is not None,'Пользователь не найден',404)
    c.execute('UPDATE users SET active=? WHERE id=?',(int(b['active']),uid))
    if not b['active']:c.execute('DELETE FROM sessions WHERE user_id=?',(uid,))
    store.audit(c,u['id'],'user.active',uid,'ok',str(b['active']));c.commit();return 200,{'id':uid,'active':b['active']}
   match=re.fullmatch(r'/admin/users/(\d+)/role',path)
   if method=='POST' and match:
    require(u['role']=='admin');ident=int(match[1]);role=b.get('role')
    require(role in ('admin','director','manager','employee'),'Недопустимая роль',400)
    require(ident!=u['id'],'Нельзя изменить собственную роль администратора',400)
    row=c.execute('SELECT company FROM users WHERE id=?',(ident,)).fetchone();require(row is not None and row['company']==u['company'],'Пользователь недоступен',404)
    c.execute('UPDATE users SET role=? WHERE id=?',(role,ident));c.execute('DELETE FROM sessions WHERE user_id=?',(ident,))
    store.audit(c,u['id'],'user.role',ident,'ok',role);c.commit();return 200,{'ok':True}
   if method=='POST' and path=='/admin/stop':
    require(u['role']=='admin');require(type(b.get('stopped')) is bool,'Нужен stopped: true или false',400);c.execute("UPDATE settings SET value=? WHERE key='stopped'",('1' if b['stopped'] else '0',));store.audit(c,u['id'],'system.stop' if b['stopped'] else 'system.start');c.commit();return 200,{'stopped':b['stopped']}
   if method=='GET' and path=='/admin/audit':
    require(u['role']=='admin');return 200,{'integrity':store.audit_verify(c),'events':[dict(r) for r in c.execute('SELECT * FROM audit ORDER BY id DESC LIMIT 200')]}
   raise APIError(404,'Маршрут не найден')

def main():
 if len(sys.argv)>1 and sys.argv[1]=='seed':store.seed(reset='--reset' in sys.argv);print('Синтетические данные загружены.');return
 store.init();host=os.getenv('FOCUS_HOST','127.0.0.1');require(host in ('127.0.0.1','localhost'),'Для демо допускается только localhost',400);port=int(os.getenv('FOCUS_PORT','8000'))
 with ThreadingHTTPServer((host,port),Handler) as server:print(f'Focus demo: http://{host}:{port}',flush=True);server.serve_forever()
if __name__=='__main__':main()
