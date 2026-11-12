"""Authentication helpers and privacy boundary for model requests.

Presidio is used when installed. A conservative regex fallback keeps the local
prototype functional without making the optional NLP package a hard dependency.
Secrets are always masked before a provider request.
"""
import hashlib
import hmac
import os
import re
import secrets


def hash_password(password, min_len=12):
    if len(password) < min_len:
        raise ValueError('Пароль должен содержать не менее 12 символов')
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac('sha256', password.encode(), salt, 600_000)
    return f'pbkdf2_sha256$600000${salt.hex()}${digest.hex()}'


def check_password(password, record):
    try:
        method, rounds, salt, digest = record.split('$')
        actual = hashlib.pbkdf2_hmac('sha256', password.encode(), bytes.fromhex(salt), int(rounds)).hex()
        return method == 'pbkdf2_sha256' and hmac.compare_digest(actual, digest)
    except (ValueError, TypeError, AttributeError):
        return False


def new_token():
    return secrets.token_urlsafe(40)


def token_hash(token):
    return hashlib.sha256(token.encode()).hexdigest()


_PATTERNS = [
    (r'(?i)\b(?:sk-[A-Za-z0-9_-]{12,}|Bearer\s+[A-Za-z0-9._~+/=-]{8,})', '[СЕКРЕТ]'),
    (r'(?i)(?:password|passwd|api[_-]?key|token|пароль|ключ)\s*[:=]\s*[^\s,;]+', '[СЕКРЕТ]'),
    (r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b', '[EMAIL]'),
    (r'(?<!\w)(?:\+?\d[\d ()-]{8,}\d)(?!\w)', '[ТЕЛЕФОН/НОМЕР]'),
    (r'\bBY\d{2}[A-Z0-9]{24,30}\b', '[РЕКВИЗИТЫ]'),
    (r'\b\d{3,4}[ -]?\d{3,4}[ -]?\d{3,6}\b', '[ИДЕНТИФИКАТОР]'),
]


def _regex_redact(value):
    text = str(value)
    for pattern, replacement in _PATTERNS:
        if replacement == '[ТЕЛЕФОН/НОМЕР]':
            text = re.sub(pattern, lambda m: replacement if sum(ch.isdigit() for ch in m.group()) >= 10 else m.group(), text)
        else:
            text = re.sub(pattern, replacement, text)
    return text


def redact(text):
    """Mask common PII and secrets before any text reaches a model provider."""
    value = _regex_redact(text)
    try:
        from presidio_analyzer import AnalyzerEngine
        from presidio_anonymizer import AnonymizerEngine
        analyzer = AnalyzerEngine()
        anonymizer = AnonymizerEngine()
        results = analyzer.analyze(
            text=value,
            language='en',
            entities=['PERSON', 'LOCATION', 'IBAN_CODE', 'CREDIT_CARD', 'US_SSN', 'IP_ADDRESS'],
        )
        if results:
            value = anonymizer.anonymize(text=value, analyzer_results=results).text
    except (ImportError, RuntimeError, ValueError, OSError):
        # Regex masking remains active if Presidio or its language models are absent.
        pass
    return value


def has_unmasked_secret(text):
    """Return True if a credential-like value is still present after masking."""
    value = re.sub(r'\[(?:СЕКРЕТ|EMAIL|ТЕЛЕФОН/НОМЕР|РЕКВИЗИТЫ|ИДЕНТИФИКАТОР)\]', '', str(text))
    secret_patterns = (r'(?i)\bsk-[A-Za-z0-9_-]{12,}', r'(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{8,}',
                       r'(?i)(?:password|passwd|api[_-]?key|token|пароль|ключ)\s*[:=]\s*[^\s,;]+')
    return any(re.search(pattern, value) for pattern in secret_patterns)


def model_safe_text(text, limit=32000):
    """Sanitize outbound model text and fail closed if a credential survives."""
    safe = redact(text)[:limit]
    if has_unmasked_secret(safe):
        raise ValueError('Запрос заблокирован: обнаружены потенциальные учётные данные')
    return safe


def encrypt_ephemeral(data, key=None):
    """Encrypt bytes in memory only; never writes keys or ciphertext to the database.

    A persistent deployment must provide FOCUS_DATA_KEY via its secret manager.
    Without it, a process-local random key is used and ciphertext cannot survive restart.
    """
    try:
        from cryptography.fernet import Fernet
    except ImportError as exc:
        raise RuntimeError('Для шифрования установите пакет cryptography') from exc
    if key is None:
        key = os.getenv('FOCUS_DATA_KEY')
    if not key:
        key = _process_key()
    if isinstance(key, str):
        key = key.encode('ascii')
    return Fernet(key).encrypt(data if isinstance(data, bytes) else str(data).encode('utf-8'))


def decrypt_ephemeral(token, key=None):
    try:
        from cryptography.fernet import Fernet
    except ImportError as exc:
        raise RuntimeError('Для шифрования установите пакет cryptography') from exc
    if key is None:
        key = os.getenv('FOCUS_DATA_KEY')
    if not key:
        key = _process_key()
    if isinstance(key, str):
        key = key.encode('ascii')
    return Fernet(key).decrypt(token)


_PROCESS_KEY = None

def _process_key():
    global _PROCESS_KEY
    if _PROCESS_KEY is None:
        from cryptography.fernet import Fernet
        _PROCESS_KEY = Fernet.generate_key()
    return _PROCESS_KEY
