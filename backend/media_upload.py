"""Explicitly selected, bounded audio uploads to OpenAI; no background file scanning."""
import json
import os
from pathlib import Path
import secrets
from urllib.parse import urlparse,unquote
import urllib.request
import urllib.error
import providers


def transcribe(value):
    if os.getenv('FOCUS_DEFAULT_PROVIDER')!='openai' or os.getenv('FOCUS_ALLOW_EXTERNAL')!='1':
        raise providers.ProviderError('Для расшифровки выберите OpenAI и разрешите передачу выбранной записи в настройках.')
    key=os.getenv('OPENAI_API_KEY')
    if not key:raise providers.ProviderError('Сначала подключите ключ OpenAI')
    if not isinstance(value,str) or not value or len(value)>4000:raise ValueError('Выберите файл')
    if value.startswith('file:'):
        parsed=urlparse(value)
        if parsed.netloc not in ('','localhost'):raise ValueError('Только локальные файлы')
        value=unquote(parsed.path)
        if os.name=='nt' and len(value)>2 and value[0]=='/' and value[2]==':':value=value[1:]
    path=Path(value)
    if not path.is_absolute() or str(path).startswith('\\\\') or path.is_symlink() or any(x.is_symlink() for x in path.parents):raise ValueError('Выберите обычный локальный файл')
    if path.suffix.lower() not in ('.mp3','.mp4','.m4a','.wav','.webm','.ogg','.flac','.mpeg','.mpga'):raise ValueError('Формат записи не поддерживается')
    stat=path.stat()
    if not path.is_file() or not 0<stat.st_size<=25*1024*1024:raise ValueError('Размер записи должен быть от 1 байта до 25 МБ')
    audio=path.read_bytes();after=path.stat()
    if (stat.st_size,stat.st_mtime_ns,stat.st_ino)!=(after.st_size,after.st_mtime_ns,after.st_ino):raise ValueError('Файл изменился во время чтения')
    boundary='focus-'+secrets.token_hex(16)
    model=os.getenv('OPENAI_TRANSCRIBE_MODEL','gpt-transcribe')
    body=(f'--{boundary}\r\nContent-Disposition: form-data; name="model"\r\n\r\n{model}\r\n'
          f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="meeting{path.suffix.lower()}"\r\nContent-Type: application/octet-stream\r\n\r\n').encode()+audio+f'\r\n--{boundary}--\r\n'.encode()
    request=urllib.request.Request('https://api.openai.com/v1/audio/transcriptions',body,
        {'Authorization':'Bearer '+key,'Content-Type':'multipart/form-data; boundary='+boundary})
    try:
        with urllib.request.build_opener(providers.NoRedirect()).open(request,timeout=180) as response:result=json.load(response)
    except urllib.error.HTTPError as exc:
        if exc.code==429:raise providers.ProviderError('Лимит или баланс API OpenAI исчерпан. Проверьте баланс API.') from exc
        raise providers.ProviderError(f'Не удалось расшифровать запись: HTTP {exc.code}') from exc
    except (OSError,ValueError) as exc:raise providers.ProviderError('Сервис расшифровки недоступен. Повторите позже.') from exc
    text=result.get('text')
    if not isinstance(text,str) or not text.strip():raise providers.ProviderError('Сервис не вернул расшифровку')
    return text[:100000]
