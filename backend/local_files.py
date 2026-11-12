"""Safe, explicit local-file reads for the development server.

File grants remain read-only. Importing a document copies only extracted text
into the user's Focus workspace after they choose a file in the desktop UI.
"""
import os,stat,io,zipfile,shutil,subprocess,xml.etree.ElementTree as ET
from pathlib import Path
MAX_FILE=5*1024*1024
MAX_XML=10*1024*1024
MAX_OUTPUT=100_000
SUPPORTED={'.txt','.md','.csv','.json','.docx','.pdf'}
class FileAccessError(Exception):pass

def file_identity(value):
 # Python 3.12+ can expose 128-bit Windows file IDs. SQLite INTEGER is signed
 # 64-bit; a nonnumeric prefix preserves every bit without REAL coercion.
 return value if -(2**63)<=value<2**63 else 'wide:'+format(value,'x')

def path_syntax(path):
 if not isinstance(path,str) or not path.strip() or '\x00' in path or len(path)>4000:raise FileAccessError('Некорректный путь')
 if not os.path.isabs(path):raise FileAccessError('Укажите абсолютный путь к файлу')
 if Path(path).suffix.lower() not in SUPPORTED:raise FileAccessError('Формат не поддерживается: используйте TXT, MD, CSV, JSON, DOCX или PDF')
 return os.path.abspath(path)

def inspect_file(path):
 path=path_syntax(path);p=Path(path)
 # Do not follow links/junctions. Recheck on every read; platform-level races remain possible.
 for component in (p,*p.parents):
  if component.is_symlink() or (hasattr(component,'is_junction') and component.is_junction()):raise FileAccessError('Символические ссылки и соединения папок не поддерживаются')
 try:info=os.stat(path,follow_symlinks=False)
 except OSError as e:raise FileAccessError('Файл не найден или недоступен системе') from e
 if not stat.S_ISREG(info.st_mode):raise FileAccessError('Можно разрешить только обычный файл')
 if info.st_size>MAX_FILE:raise FileAccessError('Размер файла превышает 5 МБ')
 return {'path':path,'name':p.name,'extension':p.suffix.lower(),'dev':file_identity(info.st_dev),'ino':file_identity(info.st_ino),'size':info.st_size}

def extract(data,ext):
 if ext in ('.txt','.md','.csv','.json'):
  try:return data.decode('utf-8-sig')
  except UnicodeDecodeError as e:raise FileAccessError('Текстовый файл должен быть в кодировке UTF-8') from e
 if ext=='.docx':
  try:
   with zipfile.ZipFile(io.BytesIO(data)) as z:
    item=z.getinfo('word/document.xml')
    if item.file_size>MAX_XML:raise FileAccessError('Содержимое DOCX слишком большое')
    root=ET.fromstring(z.read(item))
   ns={'w':'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
   text='\n'.join(''.join(x.text or '' for x in p.findall('.//w:t',ns)) for p in root.findall('.//w:p',ns))
   if not text.strip():raise FileAccessError('В DOCX не найден текст; изображения и сканы не распознаются')
   return text
  except (zipfile.BadZipFile,KeyError,ET.ParseError) as e:raise FileAccessError('Повреждённый или неподдерживаемый DOCX') from e
 if ext=='.pdf':
  # Optional: pypdf has to be installed by the user. No download happens here.
  try:
   from pypdf import PdfReader
   reader=PdfReader(io.BytesIO(data));
   if reader.is_encrypted:raise FileAccessError('Защищённый паролем PDF пока не поддерживается')
   if len(reader.pages)>100:raise FileAccessError('В PDF больше 100 страниц')
   text='\n'.join(page.extract_text() or '' for page in reader.pages)
  except ImportError:
   executable=shutil.which('pdftotext')
   if not executable:raise FileAccessError('Для PDF установите pypdf: py -m pip install pypdf')
   try:
    process=subprocess.run([executable,'-','-'],input=data,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,timeout=15,check=True)
    text=process.stdout.decode('utf-8',errors='replace')
   except (subprocess.SubprocessError,OSError) as e:raise FileAccessError('Не удалось извлечь текст PDF') from e
  except FileAccessError:raise
  except Exception as e:raise FileAccessError('Не удалось извлечь текст PDF') from e
  if not text.strip():raise FileAccessError('В PDF нет извлекаемого текста; распознавание сканов пока не реализовано')
  return text
 raise FileAccessError('Формат не поддерживается')

def read_granted(grant):
 info=inspect_file(grant['path'])
 if info['dev']!=grant['dev'] or info['ino']!=grant['ino']:raise FileAccessError('Файл заменён; требуется новое разрешение')
 flags=os.O_RDONLY|getattr(os,'O_BINARY',0)|getattr(os,'O_NOFOLLOW',0)
 try:
  fd=os.open(info['path'],flags)
  with os.fdopen(fd,'rb') as f:
   st=os.fstat(f.fileno())
   if not stat.S_ISREG(st.st_mode) or file_identity(st.st_dev)!=grant['dev'] or file_identity(st.st_ino)!=grant['ino']:raise FileAccessError('Файл изменился; требуется новое разрешение')
   raw=f.read(MAX_FILE+1)
 except OSError as e:raise FileAccessError('Не удалось открыть разрешённый файл') from e
 if len(raw)>MAX_FILE:raise FileAccessError('Размер файла превышает 5 МБ')
 text=extract(raw,info['extension'])
 if len(text)>MAX_OUTPUT:raise FileAccessError('Извлечённый текст превышает 100 000 символов')
 return text

def read_path(path):
 """Read one explicitly selected file and return its checked metadata and text."""
 info=inspect_file(path)
 grant={'path':info['path'],'dev':info['dev'],'ino':info['ino']}
 return info,read_granted(grant)
