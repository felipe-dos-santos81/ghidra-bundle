"""Unit tests for bundle_mpq (python/bundle-mpq). `make test` runs them with the PyGhidra
venv's Python; by hand:

    PYTHONPATH=python/bundle-mpq python3 tests/test_bundle_mpq.py

Archive tests are skipped when StormLib (libstorm) is missing.
"""
import os
import sys
import tempfile
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
