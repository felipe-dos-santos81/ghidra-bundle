import runpy
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "prepare-extension-source.py"
NAMESPACE = runpy.run_path(str(SCRIPT))
PatchError = NAMESPACE["PatchError"]
patch_source = NAMESPACE["patch_source"]
prepare_source = NAMESPACE["prepare_source"]

DATA_TYPE_RELATIVE_PATH = Path("src/main/java/com/xebyte/core/DataTypeService.java")
OLD_DATA_TYPE_CALL = "dtm.remove(dataType, null)"
OLD_EXISTING_CALL = "dtm.remove(existing, null)"
NEW_DATA_TYPE_CALL = "dtm.remove(dataType)"
NEW_EXISTING_CALL = "dtm.remove(existing)"
SOURCE = """class DataTypeService {
    void deletePlaceholderType() {
        boolean deleted = dtm.remove(dataType, null);
        deleted = dtm.remove(existing, null);
    }
    void deleteDataType() {
        boolean deleted = dtm.remove(dataType, null);
    }
}
"""
PATCHED_SOURCE = """class DataTypeService {
    void deletePlaceholderType() {
        boolean deleted = dtm.remove(dataType);
        deleted = dtm.remove(existing);
    }
    void deleteDataType() {
        boolean deleted = dtm.remove(dataType);
    }
}
"""


def tree_bytes(root):
    return {
        str(path.relative_to(root)): path.read_bytes()
        for path in root.rglob("*")
        if path.is_file()
    }


class PrepareGhidraMcpTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.destination = self.root / "dist" / "build" / "ghidra-mcp"

    def tearDown(self):
        self.temporary.cleanup()

    def make_source(self, content=SOURCE):
        source = self.root / "source"
        data_type = source / DATA_TYPE_RELATIVE_PATH
        data_type.parent.mkdir(parents=True)
        data_type.write_text(content, encoding="utf-8")
        (source / "settings.gradle").write_text(
            "rootProject.name = 'GhidraMCP'\n", encoding="utf-8"
        )
        return source

    def test_patch_source_replaces_three_calls_and_is_idempotent(self):
        patched = patch_source("ghidra-mcp", SOURCE, "12.2")
        self.assertEqual(PATCHED_SOURCE, patched)
        self.assertEqual(2, patched.count(NEW_DATA_TYPE_CALL))
        self.assertEqual(1, patched.count(NEW_EXISTING_CALL))
        self.assertEqual(patched, patch_source("ghidra-mcp", patched, "12.2"))

    def test_prepare_source_creates_fresh_copy_and_preserves_original(self):
        source = self.make_source()
        original = tree_bytes(source)
        self.destination.mkdir(parents=True)
        (self.destination / "stale.txt").write_text("stale", encoding="utf-8")

        self.assertIsNone(prepare_source("ghidra-mcp", source, self.destination, "12.2"))

        self.assertFalse((self.destination / "stale.txt").exists())
        self.assertEqual(
            "rootProject.name = 'GhidraMCP'\n",
            (self.destination / "settings.gradle").read_text(encoding="utf-8"),
        )
        self.assertEqual(
            PATCHED_SOURCE,
            (self.destination / DATA_TYPE_RELATIVE_PATH).read_text(encoding="utf-8"),
        )
        self.assertEqual(original, tree_bytes(source))

    def test_prepare_source_excludes_generated_metadata(self):
        source = self.make_source()
        (source / ".git").write_text("gitdir: /unused\n", encoding="utf-8")
        for name in (".gradle", "build", "target", "dist", "__pycache__"):
            directory = source / name
            directory.mkdir()
            (directory / "generated.txt").write_text("generated", encoding="utf-8")

        prepare_source("ghidra-mcp", source, self.destination, "12.2")

        for name in (".git", ".gradle", "build", "target", "dist", "__pycache__"):
            with self.subTest(excluded=name):
                self.assertFalse((self.destination / name).exists())
        self.assertTrue((self.destination / "settings.gradle").is_file())

    def test_prepare_source_repeat_run_produces_identical_copy(self):
        source = self.make_source()
        prepare_source("ghidra-mcp", source, self.destination, "12.2")
        first = tree_bytes(self.destination)

        prepare_source("ghidra-mcp", source, self.destination, "12.2")

        self.assertEqual(first, tree_bytes(self.destination))

    def test_rejects_other_ghidra_versions_without_copy(self):
        source = self.make_source()
        for version in ("12.1.4", "12.2.1", "12.3"):
            with self.subTest(version=version):
                with self.assertRaises(PatchError):
                    patch_source("ghidra-mcp", SOURCE, version)
        with self.assertRaises(PatchError):
            prepare_source("ghidra-mcp", source, self.destination, "12.2.1")
        self.assertFalse(self.destination.exists())

    def test_rejects_missing_duplicated_or_mixed_anchors(self):
        variants = {
            "empty": "",
            "missing dataType call": SOURCE.replace(OLD_DATA_TYPE_CALL, "", 1),
            "missing existing call": SOURCE.replace(OLD_EXISTING_CALL, "", 1),
            "duplicated old dataType call": SOURCE + OLD_DATA_TYPE_CALL,
            "duplicated old existing call": SOURCE + OLD_EXISTING_CALL,
            "duplicated new dataType call": PATCHED_SOURCE + NEW_DATA_TYPE_CALL,
            "duplicated new existing call": PATCHED_SOURCE + NEW_EXISTING_CALL,
            "mixed old and new": SOURCE.replace(OLD_DATA_TYPE_CALL, NEW_DATA_TYPE_CALL, 1),
            "partial patch": SOURCE.replace(OLD_DATA_TYPE_CALL, NEW_DATA_TYPE_CALL),
        }
        for name, content in variants.items():
            with self.subTest(variant=name):
                with self.assertRaises(PatchError):
                    patch_source("ghidra-mcp", content, "12.2")

    def test_invalid_source_does_not_replace_existing_destination(self):
        source = self.make_source("unexpected source\n")
        self.destination.mkdir(parents=True)
        sentinel = self.destination / "sentinel.txt"
        sentinel.write_text("keep", encoding="utf-8")

        with self.assertRaises(PatchError):
            prepare_source("ghidra-mcp", source, self.destination, "12.2")

        self.assertEqual("keep", sentinel.read_text(encoding="utf-8"))

    def test_overlapping_destination_cannot_modify_original(self):
        source = self.make_source()
        original = tree_bytes(source)

        with self.assertRaises(PatchError):
            prepare_source("ghidra-mcp", source, source, "12.2")

        self.assertEqual(original, tree_bytes(source))

    def test_real_pinned_source_patches_read_only(self):
        data_type = ROOT / "ghidra-mcp" / DATA_TYPE_RELATIVE_PATH
        original = data_type.read_bytes()
        source = original.decode("utf-8")
        self.assertEqual(2, source.count(OLD_DATA_TYPE_CALL))
        self.assertEqual(1, source.count(OLD_EXISTING_CALL))

        patched = patch_source("ghidra-mcp", source, "12.2")

        self.assertEqual(0, patched.count(OLD_DATA_TYPE_CALL))
        self.assertEqual(0, patched.count(OLD_EXISTING_CALL))
        self.assertEqual(2, patched.count(NEW_DATA_TYPE_CALL))
        self.assertEqual(1, patched.count(NEW_EXISTING_CALL))
        self.assertEqual(original, data_type.read_bytes())

    def test_cli_reports_clear_error_without_copy(self):
        source = self.make_source()
        result = subprocess.run(
            [
                sys.executable,
                "-I",
                str(SCRIPT),
                "ghidra-mcp",
                str(source),
                str(self.destination),
                "12.2.1",
            ],
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertNotEqual(0, result.returncode)
        self.assertIn("ERROR", result.stderr)
        self.assertIn("12.2.1", result.stderr)
        self.assertFalse(self.destination.exists())


class PrepareLxLoaderTest(unittest.TestCase):
    RELATIVE_PATH = Path(
        "src/main/java/yetmorecode/ghidra/format/lx/model/DOSHeader.java"
    )
    IMPORT_BEFORE = (
        "import ghidra.app.util.bin.StructConverter;\n"
        "import ghidra.app.util.bin.format.Writeable;\n"
    )
    IMPORT_AFTER = "import ghidra.app.util.bin.StructConverter;\n"
    CLASS_BEFORE = "public class DOSHeader implements StructConverter, Writeable   {"
    CLASS_AFTER = "public class DOSHeader implements StructConverter {"
    WRITE_SIGNATURE = (
        "\tpublic void write(RandomAccessFile raf, DataConverter dc) throws IOException {"
    )
    WRITE_BEFORE = (
        "\t/**\n"
        "\t * @see ghidra.app.util.bin.format.Writeable#write(java.io.RandomAccessFile, ghidra.util.DataConverter)\n"
        "\t */\n"
        "\t@Override\n"
        + WRITE_SIGNATURE
    )
    SOURCE = (
        IMPORT_BEFORE
        + CLASS_BEFORE
        + "\n"
        + WRITE_BEFORE
        + "\n\t\traf.write(dc.getBytes(e_magic));\n"
        + "\t}\n}\n"
    )
    PATCHED_SOURCE = (
        IMPORT_AFTER
        + CLASS_AFTER
        + "\n"
        + WRITE_SIGNATURE
        + "\n\t\traf.write(dc.getBytes(e_magic));\n"
        + "\t}\n}\n"
    )

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.destination = self.root / "dist" / "build" / "lx-loader"

    def tearDown(self):
        self.temporary.cleanup()

    def make_source(self):
        source = self.root / "source"
        header = source / self.RELATIVE_PATH
        header.parent.mkdir(parents=True)
        header.write_text(self.SOURCE, encoding="utf-8")
        (source / "settings.gradle").write_text(
            "rootProject.name = 'lx-loader'\n", encoding="utf-8"
        )
        return source

    def test_lx_patch_removes_writeable_and_is_idempotent(self):
        patched = patch_source("lx-loader", self.SOURCE, "12.2")

        self.assertEqual(self.PATCHED_SOURCE, patched)
        self.assertNotIn("Writeable", patched)
        self.assertNotIn("@Override", patched)
        self.assertIn(self.WRITE_SIGNATURE, patched)
        self.assertIn("\t\traf.write(dc.getBytes(e_magic));", patched)
        self.assertEqual(patched, patch_source("lx-loader", patched, "12.2"))

    def test_prepare_lx_source_preserves_original_and_other_files(self):
        source = self.make_source()
        original = tree_bytes(source)

        prepare_source("lx-loader", source, self.destination, "12.2")

        self.assertEqual(
            self.PATCHED_SOURCE,
            (self.destination / self.RELATIVE_PATH).read_text(encoding="utf-8"),
        )
        self.assertEqual(
            "rootProject.name = 'lx-loader'\n",
            (self.destination / "settings.gradle").read_text(encoding="utf-8"),
        )
        self.assertEqual(original, tree_bytes(source))

    def test_lx_rejects_missing_duplicated_or_partial_anchors(self):
        variants = {
            "empty": "",
            "patched import only": self.SOURCE.replace(
                self.IMPORT_BEFORE, self.IMPORT_AFTER, 1
            ),
            "patched class only": self.SOURCE.replace(
                self.CLASS_BEFORE, self.CLASS_AFTER, 1
            ),
            "patched write block only": self.SOURCE.replace(
                self.WRITE_BEFORE, self.WRITE_SIGNATURE, 1
            ),
            "duplicate import": self.SOURCE.replace(
                self.IMPORT_BEFORE, self.IMPORT_BEFORE + self.IMPORT_BEFORE, 1
            ),
            "duplicate class": self.SOURCE.replace(
                self.CLASS_BEFORE, self.CLASS_BEFORE + self.CLASS_BEFORE, 1
            ),
            "missing override": self.SOURCE.replace("\t@Override\n", "", 1),
            "missing write block": self.SOURCE.replace(self.WRITE_BEFORE, "", 1),
            "duplicate patched class": self.PATCHED_SOURCE + self.CLASS_AFTER,
            "mixed patched and old": self.PATCHED_SOURCE.replace(
                self.IMPORT_AFTER, self.IMPORT_BEFORE, 1
            ),
        }
        for name, content in variants.items():
            with self.subTest(variant=name):
                with self.assertRaises(PatchError):
                    patch_source("lx-loader", content, "12.2")

    def test_real_lx_source_patches_read_only(self):
        header = ROOT / "lx-loader" / self.RELATIVE_PATH
        original = header.read_bytes()
        source = original.decode("utf-8")
        for anchor in (self.IMPORT_BEFORE, self.CLASS_BEFORE, self.WRITE_BEFORE):
            self.assertEqual(1, source.count(anchor))

        patched = patch_source("lx-loader", source, "12.2")

        for anchor in (self.IMPORT_BEFORE, self.CLASS_BEFORE, self.WRITE_BEFORE):
            self.assertEqual(0, patched.count(anchor))
        for anchor in (self.IMPORT_AFTER, self.CLASS_AFTER, self.WRITE_SIGNATURE):
            self.assertEqual(1, patched.count(anchor))
        self.assertNotIn("Writeable", patched)
        self.assertIn("\t\traf.write(dc.getBytes(e_magic));", patched)
        self.assertEqual(original, header.read_bytes())


class PrepareDosToolboxTest(unittest.TestCase):
    RELATIVE_PATH = Path("src/main/java/ghidradostoolbox/DosLoader.java")
    OLD_CONDITION = (
        "if (header.isDosSignature() && !header.hasNewExeHeader() && !header.hasPeHeader()) {"
    )
    NEW_CONDITION = "if (header.isDosSignature()) {"
    SOURCE = (
        "class DosLoader {\n"
        "    void findSupportedLoadSpecs() {\n"
        "        "
        + OLD_CONDITION
        + "\n            loadSpecs.add(spec);\n"
        + "    }\n}\n"
    )
    PATCHED_SOURCE = (
        "class DosLoader {\n"
        "    void findSupportedLoadSpecs() {\n"
        "        "
        + NEW_CONDITION
        + "\n            loadSpecs.add(spec);\n"
        + "    }\n}\n"
    )

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.destination = self.root / "dist" / "build" / "dos-toolbox"

    def tearDown(self):
        self.temporary.cleanup()

    def make_source(self):
        source = self.root / "source"
        loader = source / self.RELATIVE_PATH
        loader.parent.mkdir(parents=True)
        loader.write_text(self.SOURCE, encoding="utf-8")
        (source / "settings.gradle").write_text(
            "rootProject.name = 'dos-toolbox'\n", encoding="utf-8"
        )
        return source

    def test_dos_patch_simplifies_exact_condition_and_is_idempotent(self):
        patched = patch_source("dos-toolbox", self.SOURCE, "12.2")

        self.assertEqual(self.PATCHED_SOURCE, patched)
        self.assertNotIn("hasNewExeHeader", patched)
        self.assertNotIn("hasPeHeader", patched)
        self.assertIn("loadSpecs.add(spec);", patched)
        self.assertEqual(patched, patch_source("dos-toolbox", patched, "12.2"))

    def test_prepare_dos_source_preserves_original_and_other_files(self):
        source = self.make_source()
        original = tree_bytes(source)

        prepare_source("dos-toolbox", source, self.destination, "12.2")

        self.assertEqual(
            self.PATCHED_SOURCE,
            (self.destination / self.RELATIVE_PATH).read_text(encoding="utf-8"),
        )
        self.assertEqual(
            "rootProject.name = 'dos-toolbox'\n",
            (self.destination / "settings.gradle").read_text(encoding="utf-8"),
        )
        self.assertEqual(original, tree_bytes(source))

    def test_dos_rejects_missing_duplicated_or_partial_anchors(self):
        variants = {
            "empty": "",
            "missing new-exe check": self.SOURCE.replace(
                " && !header.hasNewExeHeader()", "", 1
            ),
            "missing PE check": self.SOURCE.replace(" && !header.hasPeHeader()", "", 1),
            "duplicate old condition": self.SOURCE + self.OLD_CONDITION,
            "duplicate new condition": self.PATCHED_SOURCE + self.NEW_CONDITION,
            "mixed old and new": self.SOURCE + self.NEW_CONDITION,
            "wrong condition": self.SOURCE.replace(
                self.OLD_CONDITION, "if (!header.isDosSignature()) {", 1
            ),
        }
        for name, content in variants.items():
            with self.subTest(variant=name):
                with self.assertRaises(PatchError):
                    patch_source("dos-toolbox", content, "12.2")

    def test_real_dos_source_patches_read_only(self):
        loader = ROOT / "dos-toolbox" / self.RELATIVE_PATH
        original = loader.read_bytes()
        source = original.decode("utf-8")
        self.assertEqual(1, source.count(self.OLD_CONDITION))
        self.assertEqual(0, source.count(self.NEW_CONDITION))

        patched = patch_source("dos-toolbox", source, "12.2")

        self.assertEqual(0, patched.count(self.OLD_CONDITION))
        self.assertEqual(1, patched.count(self.NEW_CONDITION))
        self.assertNotIn("hasNewExeHeader", patched)
        self.assertNotIn("hasPeHeader", patched)
        self.assertIn("QueryOpinionService.query", patched)
        self.assertEqual(original, loader.read_bytes())


class PrepareGhidrAssistTest(unittest.TestCase):
    RELATIVE_PATH = Path(
        "src/main/java/ghidrassist/workers/SwingWorkerTaskMonitor.java"
    )
    CHECK_SIGNATURE = (
        "    public void checkCanceled() throws ghidra.util.exception.CancelledException {"
    )
    CHECK_BEFORE = (
        "    @SuppressWarnings(\"deprecation\")\n    @Override\n" + CHECK_SIGNATURE
    )
    CHECK_AFTER = "    @SuppressWarnings(\"deprecation\")\n" + CHECK_SIGNATURE
    CLEAR_SIGNATURE = "    public void clearCanceled() {"
    CLEAR_BEFORE = (
        "    @SuppressWarnings(\"deprecation\")\n    @Override\n" + CLEAR_SIGNATURE
    )
    CLEAR_AFTER = "    @SuppressWarnings(\"deprecation\")\n" + CLEAR_SIGNATURE
    SOURCE = (
        "class SwingWorkerTaskMonitor {\n"
        + CHECK_BEFORE
        + "\n        checkCancelled();\n    }\n"
        + CLEAR_BEFORE
        + "\n        clearCancelled();\n    }\n}\n"
    )
    PATCHED_SOURCE = (
        "class SwingWorkerTaskMonitor {\n"
        + CHECK_AFTER
        + "\n        checkCancelled();\n    }\n"
        + CLEAR_AFTER
        + "\n        clearCancelled();\n    }\n}\n"
    )

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.destination = self.root / "dist" / "build" / "ghidrassist"

    def tearDown(self):
        self.temporary.cleanup()

    def make_source(self):
        source = self.root / "source"
        monitor = source / self.RELATIVE_PATH
        monitor.parent.mkdir(parents=True)
        monitor.write_text(self.SOURCE, encoding="utf-8")
        (source / "settings.gradle").write_text(
            "rootProject.name = 'GhidrAssist'\n", encoding="utf-8"
        )
        return source

    def test_ghidrassist_patch_removes_only_stale_overrides_and_is_idempotent(self):
        patched = patch_source("ghidrassist", self.SOURCE, "12.2")

        self.assertEqual(self.PATCHED_SOURCE, patched)
        self.assertNotIn("@Override", patched)
        self.assertIn(self.CHECK_SIGNATURE, patched)
        self.assertIn(self.CLEAR_SIGNATURE, patched)
        self.assertIn("checkCancelled();", patched)
        self.assertIn("clearCancelled();", patched)
        self.assertEqual(patched, patch_source("ghidrassist", patched, "12.2"))

    def test_prepare_ghidrassist_source_preserves_original_and_other_files(self):
        source = self.make_source()
        original = tree_bytes(source)

        prepare_source("ghidrassist", source, self.destination, "12.2")

        self.assertEqual(
            self.PATCHED_SOURCE,
            (self.destination / self.RELATIVE_PATH).read_text(encoding="utf-8"),
        )
        self.assertEqual(
            "rootProject.name = 'GhidrAssist'\n",
            (self.destination / "settings.gradle").read_text(encoding="utf-8"),
        )
        self.assertEqual(original, tree_bytes(source))

    def test_ghidrassist_rejects_missing_duplicated_or_partial_anchors(self):
        variants = {
            "empty": "",
            "patched check only": self.SOURCE.replace(
                self.CHECK_BEFORE, self.CHECK_AFTER, 1
            ),
            "patched clear only": self.SOURCE.replace(
                self.CLEAR_BEFORE, self.CLEAR_AFTER, 1
            ),
            "duplicate check block": self.SOURCE.replace(
                self.CHECK_BEFORE, self.CHECK_BEFORE + self.CHECK_BEFORE, 1
            ),
            "duplicate clear block": self.SOURCE.replace(
                self.CLEAR_BEFORE, self.CLEAR_BEFORE + self.CLEAR_BEFORE, 1
            ),
            "duplicate patched block": self.PATCHED_SOURCE + self.CHECK_AFTER,
            "mixed old and new": self.SOURCE + self.CHECK_AFTER,
            "missing check signature": self.SOURCE.replace(self.CHECK_SIGNATURE, "", 1),
        }
        for name, content in variants.items():
            with self.subTest(variant=name):
                with self.assertRaises(PatchError):
                    patch_source("ghidrassist", content, "12.2")

    def test_real_ghidrassist_source_patches_read_only(self):
        monitor = ROOT / "GhidrAssist" / self.RELATIVE_PATH
        original = monitor.read_bytes()
        source = original.decode("utf-8")
        self.assertEqual(1, source.count(self.CHECK_BEFORE))
        self.assertEqual(1, source.count(self.CLEAR_BEFORE))
        override_count = source.count("@Override")

        patched = patch_source("ghidrassist", source, "12.2")

        self.assertEqual(0, patched.count(self.CHECK_BEFORE))
        self.assertEqual(0, patched.count(self.CLEAR_BEFORE))
        self.assertEqual(1, patched.count(self.CHECK_AFTER))
        self.assertEqual(1, patched.count(self.CLEAR_AFTER))
        self.assertEqual(override_count - 2, patched.count("@Override"))
        self.assertIn("checkCancelled();", patched)
        self.assertIn("clearCancelled();", patched)
        self.assertEqual(original, monitor.read_bytes())


class PreparePluginGhidraTest(unittest.TestCase):
    CHAT_PATH = Path(
        "src/main/java/ai/reveng/toolkit/ghidra/chat/ui/AgentChatWindow.java"
    )
    PLUGIN_PATH = Path(
        "src/main/java/ai/reveng/toolkit/ghidra/plugins/ReaiAPIServicePlugin.java"
    )
    SERVICE_PATH = Path(
        "src/main/java/ai/reveng/toolkit/ghidra/core/services/api/GhidraRevengService.java"
    )
    TEST_PATH = Path("src/test/java/ai/reveng/ReaiAPIServicePluginTest.java")

    CHAT_BEFORE = "BrowserLoader.display(URI.create(href).toURL());"
    CHAT_AFTER = "BrowserLoader.display(URI.create(href).toURL(), null, tool);"
    PLUGIN_BEFORE = (
        "        revengService = new GhidraRevengService(apiInfo);\n"
        "        registerServiceProvided(GhidraRevengService.class, revengService);"
    )
    PLUGIN_AFTER = (
        "        revengService = new GhidraRevengService(apiInfo);\n"
        "        revengService.setBrowserServiceProvider(tool);\n"
        "        registerServiceProvided(GhidraRevengService.class, revengService);"
    )
    IMPORT_BEFORE = "import ghidra.framework.plugintool.PluginTool;\n"
    IMPORT_AFTER = (
        "import ghidra.framework.plugintool.PluginTool;\n"
        "import ghidra.framework.plugintool.ServiceProvider;\n"
    )
    FIELDS_BEFORE = (
        "    private TypedApiInterface api;\n    private ApiInfo apiInfo;\n"
    )
    FIELDS_AFTER = (
        FIELDS_BEFORE + "    private ServiceProvider browserServiceProvider;\n"
    )
    CONSTRUCTOR = (
        "    public GhidraRevengService(){\n"
        "        this.api = new MockApi();\n"
        "    }"
    )
    GET_SERVER = "    public URI getServer() {"
    ACCESSORS = (
        "    public void setBrowserServiceProvider(ServiceProvider browserServiceProvider) {\n"
        "        this.browserServiceProvider = browserServiceProvider;\n"
        "    }\n\n"
        "    public ServiceProvider getBrowserServiceProvider() {\n"
        "        return browserServiceProvider;\n"
        "    }"
    )
    SERVICE_BROWSER_BEFORE = "BrowserLoader.display(uri.toURL());"
    SERVICE_BROWSER_AFTER = (
        "BrowserLoader.display(uri.toURL(), null, browserServiceProvider);"
    )
    ASSERTION_BEFORE = (
        "        assertEquals(\"Service should be configured with the provided hostname\",\n"
        "                URI.create(\"https://api.test.reveng.ai\"), service.getServer());"
    )
    ASSERTION_AFTER = (
        ASSERTION_BEFORE
        + "\n        assertSame(\"Browser service provider should be the plugin tool\", tool,\n"
        + "                service.getBrowserServiceProvider());"
    )

    CHAT_SOURCE = "class AgentChatWindow {\n    " + CHAT_BEFORE + "\n}\n"
    CHAT_PATCHED = "class AgentChatWindow {\n    " + CHAT_AFTER + "\n}\n"
    PLUGIN_SOURCE = "class ReaiAPIServicePlugin {\n" + PLUGIN_BEFORE + "\n}\n"
    PLUGIN_PATCHED = "class ReaiAPIServicePlugin {\n" + PLUGIN_AFTER + "\n}\n"
    SERVICE_SOURCE = (
        IMPORT_BEFORE
        + "public class GhidraRevengService {\n"
        + FIELDS_BEFORE
        + CONSTRUCTOR
        + "\n\n"
        + GET_SERVER
        + "\n    }\n    "
        + SERVICE_BROWSER_BEFORE
        + "\n}\n"
    )
    SERVICE_PATCHED = (
        IMPORT_AFTER
        + "public class GhidraRevengService {\n"
        + FIELDS_AFTER
        + CONSTRUCTOR
        + "\n\n"
        + ACCESSORS
        + "\n\n"
        + GET_SERVER
        + "\n    }\n    "
        + SERVICE_BROWSER_AFTER
        + "\n}\n"
    )
    TEST_SOURCE = "class ReaiAPIServicePluginTest {\n" + ASSERTION_BEFORE + "\n}\n"
    TEST_PATCHED = "class ReaiAPIServicePluginTest {\n" + ASSERTION_AFTER + "\n}\n"
    SOURCES = {
        CHAT_PATH: CHAT_SOURCE,
        PLUGIN_PATH: PLUGIN_SOURCE,
        SERVICE_PATH: SERVICE_SOURCE,
        TEST_PATH: TEST_SOURCE,
    }
    PATCHED_SOURCES = {
        CHAT_PATH: CHAT_PATCHED,
        PLUGIN_PATH: PLUGIN_PATCHED,
        SERVICE_PATH: SERVICE_PATCHED,
        TEST_PATH: TEST_PATCHED,
    }

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.destination = self.root / "dist" / "build" / "plugin-ghidra"

    def tearDown(self):
        self.temporary.cleanup()

    def make_source(self, omit=None):
        source = self.root / "source"
        for relative_path, content in self.SOURCES.items():
            if relative_path == omit:
                continue
            path = source / relative_path
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
        (source / "settings.gradle").write_text(
            "rootProject.name = 'plugin-ghidra'\n", encoding="utf-8"
        )
        return source

    def test_plugin_multi_file_patch_applies_all_changes_and_is_idempotent(self):
        for relative_path, source in self.SOURCES.items():
            with self.subTest(path=str(relative_path)):
                patched = patch_source(
                    "plugin-ghidra", source, "12.2", relative_path
                )
                self.assertEqual(self.PATCHED_SOURCES[relative_path], patched)
                self.assertEqual(
                    patched,
                    patch_source("plugin-ghidra", patched, "12.2", relative_path),
                )
        self.assertIn("setBrowserServiceProvider(tool)", self.PLUGIN_AFTER)
        self.assertIn("null, browserServiceProvider", self.SERVICE_BROWSER_AFTER)
        self.assertIn("null, tool", self.CHAT_AFTER)
        self.assertIn("assertSame", self.ASSERTION_AFTER)

    def test_prepare_plugin_source_patches_all_and_preserves_original(self):
        source = self.make_source()
        original = tree_bytes(source)

        prepare_source("plugin-ghidra", source, self.destination, "12.2")

        for relative_path, patched in self.PATCHED_SOURCES.items():
            self.assertEqual(
                patched,
                (self.destination / relative_path).read_text(encoding="utf-8"),
            )
        self.assertEqual(
            "rootProject.name = 'plugin-ghidra'\n",
            (self.destination / "settings.gradle").read_text(encoding="utf-8"),
        )
        self.assertEqual(original, tree_bytes(source))

    def test_prepare_plugin_source_rejects_incomplete_set_without_replacement(self):
        source = self.make_source(omit=self.SERVICE_PATH)
        self.destination.mkdir(parents=True)
        sentinel = self.destination / "sentinel.txt"
        sentinel.write_text("keep", encoding="utf-8")

        with self.assertRaises(PatchError):
            prepare_source("plugin-ghidra", source, self.destination, "12.2")

        self.assertEqual("keep", sentinel.read_text(encoding="utf-8"))

    def test_plugin_rejects_partial_anchors_and_unsupported_paths(self):
        variants = (
            (self.CHAT_PATH, self.CHAT_SOURCE + self.CHAT_BEFORE),
            (self.CHAT_PATH, self.CHAT_SOURCE + self.CHAT_AFTER),
            (self.PLUGIN_PATH, self.PLUGIN_SOURCE.replace("        registerServiceProvided", "", 1)),
            (self.SERVICE_PATH, self.SERVICE_SOURCE.replace(self.IMPORT_BEFORE, self.IMPORT_AFTER, 1)),
            (self.SERVICE_PATH, self.SERVICE_SOURCE.replace(self.SERVICE_BROWSER_BEFORE, "", 1)),
            (self.TEST_PATH, self.TEST_SOURCE + self.ASSERTION_AFTER),
        )
        for relative_path, content in variants:
            with self.subTest(path=str(relative_path)):
                with self.assertRaises(PatchError):
                    patch_source("plugin-ghidra", content, "12.2", relative_path)
        with self.assertRaises(PatchError):
            patch_source("plugin-ghidra", self.CHAT_SOURCE, "12.2")
        with self.assertRaises(PatchError):
            patch_source("plugin-ghidra", self.CHAT_SOURCE, "12.2", "etc/Nope.java")
        with self.assertRaises(PatchError):
            patch_source("ghidra-mcp", SOURCE, "12.2", "etc/Nope.java")

    def test_real_plugin_sources_patch_read_only(self):
        required = {
            self.CHAT_PATH: (self.CHAT_AFTER,),
            self.PLUGIN_PATH: (self.PLUGIN_AFTER,),
            self.SERVICE_PATH: (
                self.IMPORT_AFTER,
                self.FIELDS_AFTER,
                self.ACCESSORS,
                self.SERVICE_BROWSER_AFTER,
            ),
            self.TEST_PATH: (self.ASSERTION_AFTER,),
        }
        for relative_path, anchors in required.items():
            with self.subTest(path=str(relative_path)):
                path = ROOT / "plugin-ghidra" / relative_path
                original = path.read_bytes()
                patched = patch_source(
                    "plugin-ghidra", original.decode("utf-8"), "12.2", relative_path
                )
                for anchor in anchors:
                    self.assertIn(anchor, patched)
                self.assertEqual(original, path.read_bytes())


class PrepareGhidraFindcryptTest(unittest.TestCase):
    RELATIVE_PATH = Path("src/main/java/findcrypt/FindCryptAnalyzer.java")
    OLD_CALL = "monitor.checkCanceled();"
    NEW_CALL = "monitor.checkCancelled();"
    SOURCE = (
        "class FindCryptAnalyzer {\n"
        "    void analyze() {\n"
        "        monitor.checkCanceled();\n"
        "        while (searching) {\n"
        "            monitor.checkCanceled();\n"
        "        }\n"
        "    }\n"
        "}\n"
    )
    PATCHED_SOURCE = (
        "class FindCryptAnalyzer {\n"
        "    void analyze() {\n"
        "        monitor.checkCancelled();\n"
        "        while (searching) {\n"
        "            monitor.checkCancelled();\n"
        "        }\n"
        "    }\n"
        "}\n"
    )

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.destination = self.root / "dist" / "build" / "GhidraFindcrypt"

    def tearDown(self):
        self.temporary.cleanup()

    def make_source(self):
        source = self.root / "source"
        analyzer = source / self.RELATIVE_PATH
        analyzer.parent.mkdir(parents=True)
        analyzer.write_text(self.SOURCE, encoding="utf-8")
        (source / "settings.gradle").write_text(
            "rootProject.name = 'GhidraFindcrypt'\n", encoding="utf-8"
        )
        return source

    def test_findcrypt_patch_updates_both_calls_and_is_idempotent(self):
        patched = patch_source("ghidrafindcrypt", self.SOURCE, "12.2")

        self.assertEqual(self.PATCHED_SOURCE, patched)
        self.assertEqual(2, patched.count(self.NEW_CALL))
        self.assertNotIn(self.OLD_CALL, patched)
        self.assertEqual(patched, patch_source("ghidrafindcrypt", patched, "12.2"))

    def test_prepare_findcrypt_source_preserves_original_and_other_files(self):
        source = self.make_source()
        original = tree_bytes(source)

        prepare_source("ghidrafindcrypt", source, self.destination, "12.2")

        self.assertEqual(
            self.PATCHED_SOURCE,
            (self.destination / self.RELATIVE_PATH).read_text(encoding="utf-8"),
        )
        self.assertEqual(
            "rootProject.name = 'GhidraFindcrypt'\n",
            (self.destination / "settings.gradle").read_text(encoding="utf-8"),
        )
        self.assertEqual(original, tree_bytes(source))

    def test_findcrypt_rejects_missing_duplicated_or_partial_anchors(self):
        variants = {
            "empty": "",
            "missing call": self.SOURCE.replace(self.OLD_CALL, "", 1),
            "duplicate old call": self.SOURCE + self.OLD_CALL,
            "duplicate new call": self.PATCHED_SOURCE + self.NEW_CALL,
            "mixed old and new": self.SOURCE + self.NEW_CALL,
            "partial patch": self.SOURCE.replace(self.OLD_CALL, self.NEW_CALL, 1),
        }
        for name, content in variants.items():
            with self.subTest(variant=name):
                with self.assertRaises(PatchError):
                    patch_source("ghidrafindcrypt", content, "12.2")

    def test_real_findcrypt_source_patches_read_only(self):
        analyzer = ROOT / "GhidraFindcrypt" / self.RELATIVE_PATH
        original = analyzer.read_bytes()
        source = original.decode("utf-8")
        self.assertEqual(2, source.count(self.OLD_CALL))
        self.assertEqual(0, source.count(self.NEW_CALL))

        patched = patch_source("ghidrafindcrypt", source, "12.2")

        self.assertEqual(0, patched.count(self.OLD_CALL))
        self.assertEqual(2, patched.count(self.NEW_CALL))
        self.assertIn("findBytes", patched)
        self.assertEqual(original, analyzer.read_bytes())


class PrepareExtensionSourceTest(unittest.TestCase):
    def test_unknown_extension_is_rejected(self):
        with self.assertRaises(PatchError):
            patch_source("unknown-extension", "", "12.2")


if __name__ == "__main__":
    unittest.main()
