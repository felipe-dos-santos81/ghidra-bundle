#!/usr/bin/env python3
import shutil
import sys
from pathlib import Path

GHIDRA_VERSION = "12.2"
LX_WRITE_SIGNATURE = (
    "\tpublic void write(RandomAccessFile raf, DataConverter dc) throws IOException {"
)
REVENG_ACCESSORS = (
    "    public void setBrowserServiceProvider(ServiceProvider browserServiceProvider) {\n"
    "        this.browserServiceProvider = browserServiceProvider;\n"
    "    }\n\n"
    "    public ServiceProvider getBrowserServiceProvider() {\n"
    "        return browserServiceProvider;\n"
    "    }"
)
EXTENSIONS = {
    "ghidra-mcp": (
        (
            Path("src/main/java/com/xebyte/core/DataTypeService.java"),
            (
                ("dtm.remove(dataType, null)", "dtm.remove(dataType)", 2),
                ("dtm.remove(existing, null)", "dtm.remove(existing)", 1),
            ),
        ),
    ),
    "lx-loader": (
        (
            Path("src/main/java/yetmorecode/ghidra/format/lx/model/DOSHeader.java"),
            (
                (
                    "import ghidra.app.util.bin.StructConverter;\n"
                    "import ghidra.app.util.bin.format.Writeable;\n",
                    "import ghidra.app.util.bin.StructConverter;\n",
                    1,
                ),
                (
                    "public class DOSHeader implements StructConverter, Writeable   {",
                    "public class DOSHeader implements StructConverter {",
                    1,
                ),
                (
                    "\t/**\n"
                    "\t * @see ghidra.app.util.bin.format.Writeable#write(java.io.RandomAccessFile, ghidra.util.DataConverter)\n"
                    "\t */\n"
                    "\t@Override\n"
                    + LX_WRITE_SIGNATURE,
                    LX_WRITE_SIGNATURE,
                    1,
                ),
            ),
        ),
    ),
    "dos-toolbox": (
        (
            Path("src/main/java/ghidradostoolbox/DosLoader.java"),
            (
                (
                    "if (header.isDosSignature() && !header.hasNewExeHeader() && !header.hasPeHeader()) {",
                    "if (header.isDosSignature()) {",
                    1,
                ),
            ),
        ),
    ),
    "ghidrassist": (
        (
            Path("src/main/java/ghidrassist/workers/SwingWorkerTaskMonitor.java"),
            (
                (
                    "    @SuppressWarnings(\"deprecation\")\n"
                    "    @Override\n"
                    "    public void checkCanceled() throws ghidra.util.exception.CancelledException {",
                    "    @SuppressWarnings(\"deprecation\")\n"
                    "    public void checkCanceled() throws ghidra.util.exception.CancelledException {",
                    1,
                ),
                (
                    "    @SuppressWarnings(\"deprecation\")\n"
                    "    @Override\n"
                    "    public void clearCanceled() {",
                    "    @SuppressWarnings(\"deprecation\")\n"
                    "    public void clearCanceled() {",
                    1,
                ),
            ),
        ),
    ),
    "ghidrafindcrypt": (
        (
            Path("src/main/java/findcrypt/FindCryptAnalyzer.java"),
            (
                (
                    "monitor.checkCanceled();",
                    "monitor.checkCancelled();",
                    2,
                ),
            ),
        ),
    ),
    "plugin-ghidra": (
        (
            Path("src/main/java/ai/reveng/toolkit/ghidra/chat/ui/AgentChatWindow.java"),
            (
                (
                    "BrowserLoader.display(URI.create(href).toURL());",
                    "BrowserLoader.display(URI.create(href).toURL(), null, tool);",
                    1,
                ),
            ),
        ),
        (
            Path("src/main/java/ai/reveng/toolkit/ghidra/plugins/ReaiAPIServicePlugin.java"),
            (
                (
                    "        revengService = new GhidraRevengService(apiInfo);\n"
                    "        registerServiceProvided(GhidraRevengService.class, revengService);",
                    "        revengService = new GhidraRevengService(apiInfo);\n"
                    "        revengService.setBrowserServiceProvider(tool);\n"
                    "        registerServiceProvided(GhidraRevengService.class, revengService);",
                    1,
                ),
            ),
        ),
        (
            Path("src/main/java/ai/reveng/toolkit/ghidra/core/services/api/GhidraRevengService.java"),
            (
                (
                    "import ghidra.framework.plugintool.PluginTool;\n",
                    "import ghidra.framework.plugintool.PluginTool;\n"
                    "import ghidra.framework.plugintool.ServiceProvider;\n",
                    1,
                ),
                (
                    "    private TypedApiInterface api;\n"
                    "    private ApiInfo apiInfo;\n",
                    "    private TypedApiInterface api;\n"
                    "    private ApiInfo apiInfo;\n"
                    "    private ServiceProvider browserServiceProvider;\n",
                    1,
                ),
                (
                    "    public GhidraRevengService(){\n"
                    "        this.api = new MockApi();\n"
                    "    }\n\n"
                    "    public URI getServer() {",
                    "    public GhidraRevengService(){\n"
                    "        this.api = new MockApi();\n"
                    "    }\n\n"
                    + REVENG_ACCESSORS
                    + "\n\n    public URI getServer() {",
                    1,
                ),
                (
                    "BrowserLoader.display(uri.toURL());",
                    "BrowserLoader.display(uri.toURL(), null, browserServiceProvider);",
                    1,
                ),
            ),
        ),
        (
            Path("src/test/java/ai/reveng/ReaiAPIServicePluginTest.java"),
            (
                (
                    "        assertEquals(\"Service should be configured with the provided hostname\",\n"
                    "                URI.create(\"https://api.test.reveng.ai\"), service.getServer());",
                    "        assertEquals(\"Service should be configured with the provided hostname\",\n"
                    "                URI.create(\"https://api.test.reveng.ai\"), service.getServer());\n"
                    "        assertSame(\"Browser service provider should be the plugin tool\", tool,\n"
                    "                service.getBrowserServiceProvider());",
                    1,
                ),
            ),
        ),
    ),
}
EXCLUDED_NAMES = (".git", ".gradle", "build", "target", "dist", "__pycache__")


class PatchError(RuntimeError):
    pass


def _entries(extension):
    try:
        return EXTENSIONS[extension]
    except KeyError as error:
        supported = ", ".join(sorted(EXTENSIONS))
        raise PatchError(
            f"unsupported extension {extension!r}: expected one of {supported}"
        ) from error


def _specification(extension, relative_path=None):
    entries = _entries(extension)
    if relative_path is None:
        if len(entries) != 1:
            raise PatchError(f"{extension} requires a relative source path")
        return entries[0]
    selected = Path(relative_path)
    for entry in entries:
        if entry[0] == selected:
            return entry
    raise PatchError(f"unsupported source path {relative_path!r} for {extension}")


def patch_source(
    extension: str, source: str, ghidra_version: str, relative_path=None
) -> str:
    relative_path, replacements = _specification(extension, relative_path)
    if ghidra_version != GHIDRA_VERSION:
        raise PatchError(
            f"refusing Ghidra {ghidra_version}: this patch only supports {GHIDRA_VERSION}"
        )
    expected_counts = tuple(count for _, _, count in replacements)
    embedded_new_counts = tuple(
        old.count(new) * count for old, new, count in replacements
    )
    embedded_old_counts = tuple(
        new.count(old) * count for old, new, count in replacements
    )
    old_counts = tuple(source.count(old) for old, _, _ in replacements)
    new_counts = tuple(source.count(new) for _, new, _ in replacements)
    if old_counts == expected_counts and new_counts == embedded_new_counts:
        patched = source
        for old, new, _ in replacements:
            patched = patched.replace(old, new)
        return patched
    if old_counts == embedded_old_counts and new_counts == expected_counts:
        return source
    raise PatchError(
        f"unexpected {relative_path} anchors for {extension}: expected a complete "
        "unpatched or patched source with no missing, mixed, partial, or duplicate forms"
    )


def prepare_source(
    extension: str,
    source_dir: Path,
    destination_dir: Path,
    ghidra_version: str,
) -> None:
    entries = _entries(extension)
    source_dir = Path(source_dir)
    destination_dir = Path(destination_dir)
    source_resolved = source_dir.resolve()
    destination_resolved = destination_dir.resolve()
    if (
        source_resolved == destination_resolved
        or source_resolved in destination_resolved.parents
        or destination_resolved in source_resolved.parents
    ):
        raise PatchError("source and destination directories must not overlap")

    patched = {}
    for relative_path, _ in entries:
        source_path = source_dir / relative_path
        try:
            original = source_path.read_text(encoding="utf-8")
        except OSError as error:
            raise PatchError(f"cannot read required source file {source_path}: {error}") from error
        patched[relative_path] = patch_source(
            extension, original, ghidra_version, relative_path
        )

    if destination_dir.is_symlink() or destination_dir.is_file():
        destination_dir.unlink()
    elif destination_dir.exists():
        shutil.rmtree(destination_dir)
    shutil.copytree(
        source_dir,
        destination_dir,
        ignore=shutil.ignore_patterns(*EXCLUDED_NAMES),
    )
    for relative_path, content in patched.items():
        (destination_dir / relative_path).write_text(content, encoding="utf-8")


def main(argv=None) -> int:
    arguments = sys.argv[1:] if argv is None else argv
    if len(arguments) != 4:
        print(
            "usage: prepare-extension-source.py <extension> <source-dir> <destination-dir> <ghidra-version>",
            file=sys.stderr,
        )
        return 2
    try:
        prepare_source(
            arguments[0], Path(arguments[1]), Path(arguments[2]), arguments[3]
        )
    except (OSError, PatchError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
