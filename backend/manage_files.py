#!/usr/bin/env python3
"""Simple VS Code terminal helper for per-file grants and local AI chat."""
import os,sys,json,uuid,getpass,urllib.request,urllib.error
from pathlib import Path
BASE='http://127.0.0.1:'+os.getenv('FOCUS_PORT','8000')
ROOT=Path(__file__).resolve().parent

def request(method,path,data=None,token=None):
 headers={'Content-Type':'application/json; charset=utf-8'}
 if token:headers['Authorization']='Bearer '+token
 req=urllib.request.Request(BASE+path,data=json.dumps(data,ensure_ascii=False).encode('utf-8') if data is not None else None,headers=headers,method=method)
 try:
  with urllib.request.urlopen(req,timeout=90) as r:return json.load(r)
 except urllib.error.HTTPError as e:
  try:message=json.load(e).get('error','Ошибка')
  except Exception:message='Ошибка сервера'
  raise RuntimeError(f'{e.code}: {message}') from e
 except urllib.error.URLError as e:raise RuntimeError('Сервер не отвечает. В первом терминале запустите py app.py') from e

def menu_files(token):
 files=request('GET','/files/grants',token=token)['files']
 if not files:print('Разрешённых файлов пока нет.')
 for f in files:print(f"  {f['id']}: {f['name']} — {f['path']}")
 return files

def main():
 print('FOCUS — ФАЙЛЫ ДЛЯ ЛОКАЛЬНОЙ ДЕМОНСТРАЦИИ')
 print('Работайте только с синтетическими данными. Скрипт не даёт доступ ко всему компьютеру.')
 user=input('Логин [manager]: ').strip() or 'manager'
 pw=getpass.getpass('Пароль [тестовый пароль manager при пустом вводе]: ')
 if not pw and user=='manager':pw='Manager-demo-2026!'
 try:token=request('POST','/auth/login',{'username':user,'password':pw})['token']
 except RuntimeError as e:print('Ошибка входа:',e);return
 while True:
  print('\n1 — разрешить чтение файла  2 — спросить агента о файле  3 — мои разрешения  4 — отозвать разрешение  5 — проверить чтение без AI  0 — выход')
  choice=input('Выберите действие: ').strip()
  try:
   if choice=='0':break
   if choice=='1':
    sample=sorted((ROOT/'test_files').rglob('*'));sample=[p for p in sample if p.is_file()]
    print('\nГотовые тестовые файлы:')
    for i,p in enumerate(sample,1):print(f'{i:2d}. {p.relative_to(ROOT)}')
    x=input('\nВведите номер или полный путь к своему файлу: ').strip().strip('"')
    if x.isdigit() and 1<=int(x)<=len(sample):path=str(sample[int(x)-1].absolute())
    else:path=os.path.abspath(os.path.expanduser(x)) if x else ''
    preview=request('POST','/proposals',{'kind':'grant_file','idempotency_key':'file-'+uuid.uuid4().hex,'payload':{'path':path}},token)
    print('\nВы разрешаете ТОЛЬКО ЧТЕНИЕ конкретного файла:');print(path)
    print('Доступ будет у текущего пользователя Focus; изменение и удаление файлов не разрешаются.')
    if input('Подтвердить? Введите да: ').strip().lower()!='да':
     request('POST',f"/proposals/{preview['proposal_id']}/cancel",{},token);print('Отменено.');continue
    result=request('POST',f"/proposals/{preview['proposal_id']}/confirm",{},token)['result'];print('Готово. ID разрешения:',result['id'])
   elif choice=='2':
    if not menu_files(token):continue
    selected=int(input('ID файла: ').strip());agent=input('Агент eva / leo / nick / robby [robby]: ').strip().lower() or 'robby';question=input('Ваш вопрос: ').strip()
    print('Отправляю текст разрешённого файла локальной модели Ollama…')
    answer=request('POST','/focus/file-chat',{'text':question,'agent':agent,'provider':'ollama','file_ids':[selected]},token)
    print('\n'+answer['agent'].upper()+' — ЧЕРНОВИК ОТВЕТА\n'+answer['answer']);print('\nИсточники:',', '.join(x['name'] for x in answer['sources']));print(answer['warning'])
   elif choice=='5':
    if not menu_files(token):continue
    fid=int(input('ID файла: ').strip());result=request('GET',f'/files/{fid}/read',token=token)
    print('\nТекст файла (первые 2000 символов):\n'+result['text'][:2000])
   elif choice=='3':menu_files(token)
   elif choice=='4':
    if not menu_files(token):continue
    fid=int(input('ID разрешения для отзыва: ').strip());request('POST',f'/files/{fid}/revoke',{},token);print('Разрешение отозвано.')
   else:print('Выберите 0, 1, 2, 3, 4 или 5.')
  except (RuntimeError,ValueError) as e:print('Ошибка:',e)
 try:request('POST','/auth/logout',{},token)
 except RuntimeError:pass
 print('Завершено.')
if __name__=='__main__':main()
