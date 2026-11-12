"""Authenticated field encryption using the current Windows user's DPAPI keys.

This does not encrypt SQLite metadata or replace role-based access checks.
No encryption key is stored in the application, database or release archive.
"""
import base64
import ctypes
import os
from ctypes import wintypes

PREFIX = 'focus-dpapi-v1:'


class StorageProtectionError(RuntimeError):
    pass


class _Blob(ctypes.Structure):
    _fields_ = [('size', wintypes.DWORD), ('data', ctypes.POINTER(ctypes.c_ubyte))]


def _crypt(raw, decrypt=False):
    if os.name != 'nt':
        raise StorageProtectionError('Защищённое локальное хранилище требует Windows')
    buffer = ctypes.create_string_buffer(raw)
    source = _Blob(len(raw), ctypes.cast(buffer, ctypes.POINTER(ctypes.c_ubyte)))
    result = _Blob()
    library = ctypes.WinDLL('crypt32', use_last_error=True)
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.LocalFree.argtypes = [ctypes.c_void_p]
    kernel.LocalFree.restype = ctypes.c_void_p
    if decrypt:
        call = library.CryptUnprotectData
        call.argtypes = [ctypes.POINTER(_Blob), ctypes.c_void_p, ctypes.c_void_p,
                         ctypes.c_void_p, ctypes.c_void_p, wintypes.DWORD, ctypes.POINTER(_Blob)]
        args = (ctypes.byref(source), None, None, None, None, 1, ctypes.byref(result))
    else:
        call = library.CryptProtectData
        call.argtypes = [ctypes.POINTER(_Blob), wintypes.LPCWSTR, ctypes.c_void_p,
                         ctypes.c_void_p, ctypes.c_void_p, wintypes.DWORD, ctypes.POINTER(_Blob)]
        args = (ctypes.byref(source), 'Focus local workspace', None, None, None, 1, ctypes.byref(result))
    call.restype = wintypes.BOOL
    if not call(*args):
        raise StorageProtectionError('Не удалось открыть защищённые данные текущей учётной записью Windows')
    try:
        return ctypes.string_at(result.data, result.size)
    finally:
        kernel.LocalFree(ctypes.cast(result.data, ctypes.c_void_p))


def seal(value):
    if value is None:
        return None
    if not isinstance(value, str):
        raise TypeError('Storage fields must be text')
    return PREFIX + base64.b64encode(_crypt(value.encode('utf-8'))).decode('ascii')


def unseal(value):
    if not isinstance(value, str) or not value.startswith(PREFIX):
        return value
    try:
        raw = base64.b64decode(value[len(PREFIX):], validate=True)
        return _crypt(raw, decrypt=True).decode('utf-8')
    except (ValueError, UnicodeError) as exc:
        raise StorageProtectionError('Повреждены защищённые данные. Исходная база сохранена.') from exc
