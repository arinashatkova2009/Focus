#!/usr/bin/env python3
"""One-command local demo launcher. Uses a free port, never resets data."""
import sys, threading, webbrowser, os, getpass
from http.server import ThreadingHTTPServer
import app, store

def choose_ai():
    # The key lives in this process only. No keys are written into the archive.
    if os.environ.get('FOCUS_DEFAULT_PROVIDER') or not sys.stdin.isatty() or '--no-browser' in sys.argv:return
    print('\nПодключение ИИ для этой сессии:')
    print('1 — OpenAI (GPT), 2 — Anthropic (Claude), 3 — Google Gemini, 4 — Ollama на вашем ПК')
    choice=input('Выберите 1–4 (Enter — Ollama): ').strip() or '4'
    choices={'1':('openai','OPENAI_API_KEY'),'2':('anthropic','ANTHROPIC_API_KEY'),'3':('gemini','GEMINI_API_KEY'),'4':('ollama',None)}
    if choice not in choices:print('Неверный выбор; выбран локальный Ollama.');choice='4'
    provider,key_name=choices[choice]
    os.environ['FOCUS_DEFAULT_PROVIDER']=provider
    if not key_name:
        print('Для Ollama установите и запустите Ollama и скачайте модель: ollama pull llama3.1')
        return
    print('Запросы, история и найденные тестовые данные будут отправляться выбранному сервису.')
    print('Условия обработки и стоимость зависят от сервиса; не вводите конфиденциальные данные.')
    if input('Согласны использовать внешний API? (y/n): ').strip().lower() not in ('y','yes','д','да'):
        print('Внешний ИИ не подключён. Перезапустите Focus, чтобы выбрать провайдера.');return
    key=os.environ.get(key_name) or getpass.getpass('Вставьте свой API-ключ (символы не отображаются): ').strip()
    if not key:print('Ключ не указан: ответы модели будут недоступны.');return
    os.environ[key_name]=key;os.environ['FOCUS_ALLOW_EXTERNAL']='1'
    print('Доступ настроен на время этого запуска; работоспособность проверится при первом вопросе.')

def main():
    choose_ai()
    print('Focus: подготавливаю демонстрационные данные…', flush=True)
    store.seed()
    try:
        server = ThreadingHTTPServer(('127.0.0.1', 8787), app.Handler)
    except OSError:
        server = ThreadingHTTPServer(('127.0.0.1', 0), app.Handler)
    address = f'http://127.0.0.1:{server.server_port}/'
    print('\nПРИЛОЖЕНИЕ FOCUS ЗАПУЩЕНО', flush=True)
    print('Откройте новый адрес ниже (не старый адрес с портом 8000):', flush=True)
    print(address, flush=True)
    print('Если браузер не открылся сам, скопируйте этот адрес в Chrome или Edge.', flush=True)
    print('Терминал оставьте открытым. Для остановки нажмите Ctrl+C.\n', flush=True)
    if '--no-browser' not in sys.argv:
        def launch():
            try: webbrowser.open(address, new=2)
            except Exception: pass
        threading.Timer(0.4, launch).start()
    try: server.serve_forever()
    except KeyboardInterrupt: print('\nFocus остановлен.', flush=True)
    finally: server.server_close()

if __name__ == '__main__': main()
