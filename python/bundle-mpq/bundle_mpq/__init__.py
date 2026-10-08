"""Read-only MPQ (Blizzard archive) access through StormLib (libstorm), via ctypes.

    from bundle_mpq import MpqArchive
    with MpqArchive("d2data.mpq") as mpq:
        names = mpq.names()                        # needs a (listfile) in the archive
        data = mpq.read("data/global/excel/Weapons.txt")

Set BUNDLE_STORMLIB to a libstorm path to use a specific library.
`python -m bundle_mpq --check` reports whether StormLib can be used.
"""
import ctypes
import ctypes.util
import os

__all__ = ["MpqArchive", "MpqError", "load_stormlib"]

_MAX_PATH = 1024              # StormPort.h, non-Windows
_MPQ_OPEN_READ_ONLY = 0x100   # STREAM_FLAG_READ_ONLY
_SFILE_OPEN_FROM_MPQ = 0
_ERROR_HANDLE_EOF = 1002      # StormPort.h, non-Windows
_SFILE_INVALID_SIZE = 0xFFFFFFFF
_DWORD = ctypes.c_uint
_HANDLE = ctypes.c_void_p


class _FindData(ctypes.Structure):  # SFILE_FIND_DATA
    _fields_ = [
        ("cFileName", ctypes.c_char * _MAX_PATH),
        ("szPlainName", ctypes.c_char_p),
        ("dwHashIndex", _DWORD),
        ("dwBlockIndex", _DWORD),
        ("dwFileSize", _DWORD),
        ("dwFileFlags", _DWORD),
        ("dwCompSize", _DWORD),
        ("dwFileTimeLo", _DWORD),
        ("dwFileTimeHi", _DWORD),
        ("lcLocale", _DWORD),
    ]


class MpqError(OSError):
    pass


def load_stormlib():
    """Load libstorm: only $BUNDLE_STORMLIB when set, else the usual library names."""
    override = os.environ.get("BUNDLE_STORMLIB")
    names = [override] if override else [
        ctypes.util.find_library("storm"), "libstorm.so.9", "libstorm.so", "libstorm.dylib",
        "/opt/homebrew/lib/libstorm.dylib", "/usr/local/lib/libstorm.dylib"]  # Homebrew
    errors = []
    for name in filter(None, names):
        try:
            lib = ctypes.CDLL(name)
        except OSError as e:
            errors.append(str(e))
            continue
        try:
            _declare(lib)
        except MpqError as e:
            errors.append(f"{name}: {e}")
            continue
        return lib
    raise MpqError("StormLib (libstorm) not found; install libstorm-dev or set BUNDLE_STORMLIB"
                   + (f" ({'; '.join(errors)})" if errors else ""))


def _declare(lib):
    """Set the ctypes signatures, and lib.bundle_last_error to StormLib's error function."""
    ptr, h = ctypes.POINTER, _HANDLE
    signatures = {
        "SFileOpenArchive": ([ctypes.c_char_p, _DWORD, _DWORD, ptr(h)], ctypes.c_bool),
        "SFileCloseArchive": ([h], ctypes.c_bool),
        "SFileOpenFileEx": ([h, ctypes.c_char_p, _DWORD, ptr(h)], ctypes.c_bool),
        "SFileGetFileSize": ([h, ptr(_DWORD)], _DWORD),
        "SFileReadFile": ([h, ctypes.c_void_p, _DWORD, ptr(_DWORD), ctypes.c_void_p], ctypes.c_bool),
        "SFileCloseFile": ([h], ctypes.c_bool),
        "SFileFindFirstFile": ([h, ctypes.c_char_p, ptr(_FindData), ctypes.c_char_p], h),
        "SFileFindNextFile": ([h, ptr(_FindData)], ctypes.c_bool),
        "SFileFindClose": ([h], ctypes.c_bool),
    }
    for name, (argtypes, restype) in signatures.items():
        function = getattr(lib, name, None)
        if function is None:
            raise MpqError(f"StormLib does not export {name}")
        function.argtypes, function.restype = argtypes, restype
    # StormLib 9.24 and later rename GetLastError to SErrGetLastError.
    last_error = getattr(lib, "SErrGetLastError", None) or getattr(lib, "GetLastError", None)
    if last_error is None:
        raise MpqError("StormLib exports neither SErrGetLastError nor GetLastError")
    last_error.argtypes, last_error.restype = [], _DWORD
    lib.bundle_last_error = last_error


_stormlib = None


def _shared_stormlib():
    """StormLib loaded once per process, for MpqArchive."""
    global _stormlib
    if _stormlib is None:
        _stormlib = load_stormlib()
    return _stormlib


class MpqArchive:
    """A read-only MPQ archive."""

    def __init__(self, path):
        self._lib = _shared_stormlib()
        self._handle = _HANDLE()
        if not self._lib.SFileOpenArchive(os.fsencode(path), 0, _MPQ_OPEN_READ_ONLY,
                                          ctypes.byref(self._handle)):
            self._handle = _HANDLE()
            raise MpqError(f"cannot open MPQ {path} (StormLib error {self._lib.bundle_last_error()})")

    def close(self):
        if self._handle:
            self._lib.SFileCloseArchive(self._handle)
            self._handle = _HANDLE()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()

    def _check_open(self):
        if not self._handle:
            raise MpqError("MPQ archive is closed")

    def names(self, mask="*"):
        """Names of the files in the archive (read from its (listfile))."""
        self._check_open()
        data = _FindData()
        find = self._lib.SFileFindFirstFile(self._handle, mask.encode("latin-1"),
                                            ctypes.byref(data), None)
        if not find:
            return []
        result = []
        try:
            while True:
                result.append(data.cFileName.decode("latin-1"))
                if not self._lib.SFileFindNextFile(find, ctypes.byref(data)):
                    break
        finally:
            self._lib.SFileFindClose(find)
        return result

    def read(self, name):
        """Decompressed contents of one file. Case-insensitive; "/" works like "\\"."""
        self._check_open()
        handle = _HANDLE()
        key = name.replace("/", "\\").encode("latin-1")
        if not self._lib.SFileOpenFileEx(self._handle, key, _SFILE_OPEN_FROM_MPQ,
                                         ctypes.byref(handle)):
            raise MpqError(f"{name}: not in archive (StormLib error {self._lib.bundle_last_error()})")
        try:
            size = self._lib.SFileGetFileSize(handle, None)
            if size == _SFILE_INVALID_SIZE:
                raise MpqError(f"{name}: cannot get its size "
                               f"(StormLib error {self._lib.bundle_last_error()})")
            buf = ctypes.create_string_buffer(size)
            got = _DWORD()
            ok = self._lib.SFileReadFile(handle, buf, size, ctypes.byref(got), None)
            if (not ok and self._lib.bundle_last_error() != _ERROR_HANDLE_EOF) or got.value != size:
                raise MpqError(f"{name}: read {got.value} of {size} bytes "
                               f"(StormLib error {self._lib.bundle_last_error()})")
            return buf.raw
        finally:
            self._lib.SFileCloseFile(handle)
