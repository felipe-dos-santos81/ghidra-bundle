"""Unit tests for bundle_mpq (python/bundle-mpq). `make test` runs them with the PyGhidra
venv's Python; by hand:

    PYTHONPATH=python/bundle-mpq python3 tests/test_bundle_mpq.py

Archive tests are skipped when StormLib (libstorm) is missing.
"""
import os
import subprocess
import sys
import tempfile
import types
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bundle_mpq  # noqa: E402
from make_mpq import NAME, TEXT, write_mpq  # noqa: E402

try:
    bundle_mpq.load_stormlib()
    HAVE_STORMLIB = True
except bundle_mpq.MpqError:
    HAVE_STORMLIB = False


@unittest.skipUnless(HAVE_STORMLIB, "StormLib (libstorm) not found")
class MpqArchiveTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.tmp.name, "test.mpq")
        write_mpq(self.path, {NAME: TEXT})

    def tearDown(self):
        self.tmp.cleanup()

    def test_reads_pkware_compressed_file(self):
        with bundle_mpq.MpqArchive(self.path) as mpq:
            self.assertEqual(mpq.read(NAME), TEXT)

    def test_fixture_is_really_compressed(self):
        self.assertLess(os.path.getsize(self.path), len(TEXT))

    def test_names_come_from_the_listfile(self):
        with bundle_mpq.MpqArchive(self.path) as mpq:
            self.assertEqual(sorted(mpq.names()), sorted([NAME, "(listfile)"]))

    def test_lookup_ignores_case_and_slash_direction(self):
        with bundle_mpq.MpqArchive(self.path) as mpq:
            self.assertEqual(mpq.read(NAME.upper().replace("\\", "/")), TEXT)

    def test_missing_file_raises(self):
        with bundle_mpq.MpqArchive(self.path) as mpq:
            with self.assertRaises(bundle_mpq.MpqError):
                mpq.read("no\\such\\file.txt")

    def test_non_mpq_raises(self):
        bad = os.path.join(self.tmp.name, "bad.mpq")
        with open(bad, "wb") as f:
            f.write(b"not an archive " * 20)
        with self.assertRaises(bundle_mpq.MpqError):
            bundle_mpq.MpqArchive(bad)

    def test_closed_archive_raises(self):
        mpq = bundle_mpq.MpqArchive(self.path)
        mpq.close()
        with self.assertRaises(bundle_mpq.MpqError):
            mpq.read(NAME)


_SYMBOLS = ["SFileOpenArchive", "SFileCloseArchive", "SFileOpenFileEx", "SFileGetFileSize",
            "SFileReadFile", "SFileCloseFile", "SFileFindFirstFile", "SFileFindNextFile",
            "SFileFindClose"]


def _stub_library(*names):
    """Something shaped like a ctypes CDLL that exports only the given symbols."""
    lib = types.SimpleNamespace()
    for name in names:
        setattr(lib, name, types.SimpleNamespace(name=name))
    return lib


class DeclareTest(unittest.TestCase):
    def test_accepts_newer_stormlib_error_function(self):
        # StormLib 9.24 and later export SErrGetLastError instead of GetLastError.
        lib = _stub_library(*_SYMBOLS, "SErrGetLastError")
        bundle_mpq._declare(lib)
        self.assertEqual(lib.bundle_last_error.name, "SErrGetLastError")

    def test_accepts_older_stormlib_error_function(self):
        lib = _stub_library(*_SYMBOLS, "GetLastError")
        bundle_mpq._declare(lib)
        self.assertEqual(lib.bundle_last_error.name, "GetLastError")

    def test_missing_symbol_raises_mpq_error(self):
        with self.assertRaises(bundle_mpq.MpqError) as ctx:
            bundle_mpq._declare(_stub_library(*_SYMBOLS[1:], "GetLastError"))
        self.assertIn("SFileOpenArchive", str(ctx.exception))


class CheckCommandTest(unittest.TestCase):
    def test_check_reports_why_stormlib_is_unusable(self):
        env = dict(os.environ, BUNDLE_STORMLIB="/nonexistent/libstorm.so")
        result = subprocess.run([sys.executable, "-m", "bundle_mpq", "--check"],
                                env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("/nonexistent/libstorm.so", result.stderr)

    @unittest.skipUnless(HAVE_STORMLIB, "StormLib (libstorm) not found")
    def test_check_succeeds_with_stormlib(self):
        result = subprocess.run([sys.executable, "-m", "bundle_mpq", "--check"],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)


class LoadStormlibTest(unittest.TestCase):
    def test_bad_override_raises_mpq_error(self):
        saved = os.environ.get("BUNDLE_STORMLIB")
        os.environ["BUNDLE_STORMLIB"] = "/nonexistent/libstorm.so"
        try:
            with self.assertRaises(bundle_mpq.MpqError) as ctx:
                bundle_mpq.load_stormlib()
            self.assertIn("/nonexistent/libstorm.so", str(ctx.exception))
        finally:
            if saved is None:
                del os.environ["BUNDLE_STORMLIB"]
            else:
                os.environ["BUNDLE_STORMLIB"] = saved


if __name__ == "__main__":
    unittest.main()
