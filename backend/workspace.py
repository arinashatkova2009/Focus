"""User-scoped, encrypted interaction state for the multi-page desktop prototype."""
import base64
import datetime as dt
import io
import json
import zipfile
from xml.sax.saxutils import escape
import store

SECTIONS={'tasks','meetings','mail','calendar','documents','knowledge','users','analytics','settings','audit','chat'}


def initial():
    return {
      'preferences':{'language':'Русский','notifications':True,'sound':False,'compact':False},
      'recent':[], 'schedule':[], 'decisions':{}, 'chat':[],
      'mail':[
        {'id':'mail-1','from':'Анна Смирнова','address':'anna@example.com','subject':'Согласование бюджета запуска','tag':'Важно','status':'Непрочитано','time':'09:12','body':'Добрый день! Направляю бюджет запуска проекта «Орбита»: 840 000 ₽. Просьба проверить затраты на подрядчиков и подтвердить решение до пятницы. Анна.'},
        {'id':'mail-2','from':'Михаил Волков','address':'m.volkov@example.com','subject':'Статус интеграции CRM','tag':'Проекты','status':'Непрочитано','time':'08:45','body':'Коллеги, интеграция готова на 85%. Осталось проверить импорт контактов и закрыть два замечания. Демонстрацию предлагаем провести завтра в 11:00.'},
        {'id':'mail-3','from':'Елена Орлова','address':'elena@example.com','subject':'Повестка еженедельного совещания','tag':'Встречи','status':'Прочитано','time':'Вчера','body':'На встрече обсудим сроки релиза, загрузку команды и риски поставок. Подготовьте, пожалуйста, короткий статус по своему направлению.'},
        {'id':'mail-4','from':'Отдел закупок','address':'procurement@example.com','subject':'Коммерческие предложения получены','tag':'Документы','status':'Прочитано','time':'Вчера','body':'Получены три предложения по оборудованию. Вариант B дешевле на 12%, но срок поставки дольше на две недели. Требуется согласование критериев выбора.'}
      ],
      'demo_tasks':[
        {'id':'demo-t1','title':'Согласовать бюджет проекта «Орбита»','status':'open','priority':'Высокий','owner':'Анна Смирнова','due':'2026-11-13T15:00:00+03:00','demo':True},
        {'id':'demo-t2','title':'Подготовить демонстрацию CRM','status':'in_progress','priority':'Обычный','owner':'Михаил Волков','due':'2026-11-14T11:00:00+03:00','demo':True},
        {'id':'demo-t3','title':'Проверить договор с поставщиком','status':'review','priority':'Высокий','owner':'Елена Орлова','due':'2026-11-12T18:00:00+03:00','demo':True},
        {'id':'demo-t4','title':'Обновить базу знаний команды','status':'done','priority':'Обычный','owner':'Дмитрий Соколов','due':'2026-11-11T17:00:00+03:00','demo':True}
      ],
      'transcript':'Анна: Предлагаю завершить согласование бюджета до пятницы.\nМихаил: Интеграция CRM готова на 85%, осталось проверить импорт контактов.\nЕлена: Проверю договор и отмечу условия об ответственности.\nРешение: провести демонстрацию завтра в 11:00; подготовить статусы по рискам и срокам.',
      'trend':[62,68,65,74,72,81,78,84,88,85,91,94]
    }


def load(c,u):
    row=c.execute('SELECT payload FROM workspace_state WHERE user_id=? AND company=?',(u['id'],u['company'])).fetchone()
    if row:
        return json.loads(row['payload'])
    already_in_transaction=c.in_transaction
    c.execute('INSERT OR IGNORE INTO workspace_state(user_id,company,payload,updated) VALUES (?,?,?,?)',
              (u['id'],u['company'],store.seal(store.dump(initial())),store.now()))
    if not already_in_transaction:c.commit()
    return json.loads(c.execute('SELECT payload FROM workspace_state WHERE user_id=? AND company=?',(u['id'],u['company'])).fetchone()['payload'])


def save(c,u,value):
    c.execute('INSERT INTO workspace_state(user_id,company,payload,updated) VALUES (?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET payload=excluded.payload,updated=excluded.updated',
              (u['id'],u['company'],store.seal(store.dump(value)),store.now()))
    c.commit()


def snapshot(c,u,section,objects):
    if section not in SECTIONS:raise ValueError('Unknown workspace section')
    state=load(c,u)
    tasks=[]
    for row in objects.get('task',[]):
        data=row.get('data',{})
        status=str(data.get('status','open')).lower()
        status='done' if status in ('done','completed','завершена','выполнена') else 'in_progress' if status in ('in_progress','в работе') else 'review' if status in ('review','на проверке') else 'open'
        tasks.append({'id':row['id'],'title':row['title'],'status':status,'priority':data.get('priority','Обычный'),'due':data.get('due',''),'owner':u['name'] if row['owner_id']==u['id'] else 'Команда','raw':row,'demo':False})
    tasks+=state['demo_tasks']
    docs=[]
    for row in objects.get('document',[]):
        data=row.get('data',{})
        docs.append({'id':row['id'],'title':row['title'],'text':str(data.get('text',''))[:24000],
                     'status':data.get('approval_status','На проверке'),'version':row.get('version',1),
                     'author':data.get('author','Команда'),'folder':data.get('folder_id'), 'raw':row})
    people=[dict(row) for row in c.execute('SELECT id,name,role,department,active FROM users WHERE company=? ORDER BY name',(u['company'],))
            if u['role'] in ('admin','director') or (u['role']=='manager' and row['department']==u['department']) or row['id']==u['id']]
    events=[]
    for row in c.execute('SELECT * FROM audit ORDER BY id DESC LIMIT 300'):
        if u['role']!='admin' and row['actor_id']!=u['id']:continue
        if u['role']=='admin' and row['actor_id'] is not None:
            actor=c.execute('SELECT company FROM users WHERE id=?',(row['actor_id'],)).fetchone()
            if actor is None or actor['company']!=u['company']:continue
        item=dict(row);item['severity']='CRITICAL' if row['result']=='error' else 'WARNING' if row['result']=='denied' else 'INFO';events.append(item)
    meetings=[{'id':x['id'],'title':x['title'],'start':x['data'].get('start',''),'end':x['data'].get('end',''),'agenda':x['data'].get('agenda','')} for x in objects.get('meeting',[])]
    outbox=[dict(x) for x in c.execute('SELECT id,title,body,recipient,created FROM messages WHERE company=? AND user_id=? ORDER BY id DESC LIMIT 30',(u['company'],u['id']))]
    return {'section':section,'demo':True,'role':u['role'],'user':u['name'],'user_id':u['id'],'profile':json.loads(u['profile']),'department':u['department'],
            'tasks':tasks,'documents':docs,'people':people,'events':events,'meetings':meetings,'outbox':outbox,
            'mail':state['mail'],'schedule':state['schedule'],'recent':state['recent'],'preferences':state['preferences'],
            'transcript':state['transcript'],'trend':state['trend'],'chat':state['chat'][-60:],
            'metrics':{'tasks':len(tasks),'overdue':sum(1 for x in tasks if x['status']!='done' and str(x.get('due',''))[:10]<'2026-11-12' and x.get('due')),
                       'completed':sum(x['status']=='done' for x in tasks),'documents':len(docs),'meetings':len(meetings),'unread':sum(x['status']=='Непрочитано' for x in state['mail'])}}


def action(c,u,body,visible_ids):
    if not c.in_transaction:c.execute('BEGIN IMMEDIATE')
    state=load(c,u);kind=body.get('action')
    if kind=='move_demo_task':
        status=body.get('status')
        if status not in ('open','in_progress','review','done'):raise ValueError('Некорректный статус')
        task=next((x for x in state['demo_tasks'] if x['id']==body.get('id')),None)
        if task is None:raise ValueError('Демонстрационная задача не найдена')
        task['status']=status
    elif kind=='read_mail':
        mail=next((x for x in state['mail'] if x['id']==body.get('id')),None)
        if mail is None:raise ValueError('Письмо не найдено')
        mail['status']='Прочитано'
    elif kind=='schedule':
        title=str(body.get('title','')).strip();hour=body.get('hour')
        if not title or len(title)>250 or type(hour) is not int or not 8<=hour<=20:raise ValueError('Некорректный интервал')
        state['schedule']=[x for x in state['schedule'] if x['title']!=title]
        if any(x['hour']==hour for x in state['schedule']):raise ValueError('Этот час уже занят')
        state['schedule'].append({'title':title,'hour':hour})
    elif kind=='recent':
        ident=body.get('id')
        if ident not in visible_ids:raise ValueError('Недоступный источник')
        state['recent']=([ident]+[x for x in state['recent'] if x!=ident])[:20]
    elif kind=='preferences':
        values=body.get('values',{})
        if not isinstance(values,dict):raise ValueError('Некорректные настройки')
        for key in ('notifications','sound','compact'):
            if key in values:
                if type(values[key]) is not bool:raise ValueError('Некорректная настройка')
                state['preferences'][key]=values[key]
        if 'language' in values:
            if values['language'] not in ('Русский','English'):raise ValueError('Язык не поддерживается')
            state['preferences']['language']=values['language']
    elif kind=='transcript':
        text=body.get('text')
        if not isinstance(text,str) or len(text)>100000:raise ValueError('Слишком длинная расшифровка')
        state['transcript']=text
    else:raise ValueError('Действие не поддерживается')
    save(c,u,state);store.audit(c,u['id'],'workspace.'+kind,'','ok','Изменено личное пространство');c.commit()
    return {'ok':True}


def remember(c,u,user_text,answer,agent):
    if not c.in_transaction:c.execute('BEGIN IMMEDIATE')
    state=load(c,u)
    state['chat']=(state['chat']+[{'role':'user','text':user_text[:12000]},{'role':'assistant','text':answer[:12000],'agent':agent}])[-60:]
    save(c,u,state)


def spreadsheet(rows,title):
    if not isinstance(rows,list) or len(rows)>1000:raise ValueError('Некорректный отчёт')
    values=[[title],['Показатель / запись','Значение / описание']]
    values += [[str(row.get('title',''))[:1000],str(row.get('detail',''))[:4000]] for row in rows if isinstance(row,dict)]
    sheet=[]
    for r,items in enumerate(values,1):
        cells=''.join(f'<c r="{chr(65+i)}{r}" t="inlineStr"><is><t xml:space="preserve">{escape(v)}</t></is></c>' for i,v in enumerate(items))
        sheet.append(f'<row r="{r}">{cells}</row>')
    files={
      '[Content_Types].xml':'<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>',
      '_rels/.rels':'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
      'xl/workbook.xml':'<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Focus" sheetId="1" r:id="rId1"/></sheets></workbook>',
      'xl/_rels/workbook.xml.rels':'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>',
      'xl/worksheets/sheet1.xml':'<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><cols><col min="1" max="1" width="46" customWidth="1"/><col min="2" max="2" width="90" customWidth="1"/></cols><sheetData>'+''.join(sheet)+'</sheetData></worksheet>'}
    data=io.BytesIO()
    with zipfile.ZipFile(data,'w',zipfile.ZIP_DEFLATED) as z:
        for name,text in files.items():z.writestr(name,'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'+text)
    return {'content':base64.b64encode(data.getvalue()).decode('ascii'),'filename':'Focus-report.xlsx'}
