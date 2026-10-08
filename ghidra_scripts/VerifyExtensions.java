// Confirms that each bundled extension's classes were discovered by Ghidra's
// ClassSearcher. Prints one "VERIFY OK" or "VERIFY MISSING" line per class;
// `make verify-extensions` fails on any MISSING line.
//@category Bundle

import java.util.Set;
import java.util.stream.Collectors;

import ghidra.app.services.Analyzer;
import ghidra.app.util.opinion.Loader;
import ghidra.framework.plugintool.Plugin;
import ghidra.app.script.GhidraScript;
import ghidra.util.classfinder.ClassSearcher;
import ghidra.util.classfinder.ExtensionPoint;

public class VerifyExtensions extends GhidraScript {

	@Override
	public void run() throws Exception {
		// ClassSearcher matches on the extension point suffix (Plugin, Loader,
		// Analyzer), so each kind has to be queried through its own interface.
		check("GhidraMCP", Plugin.class, "GhidraMCPPlugin");
		check("lx-loader", Loader.class, "LeLoader");
		check("dos-toolbox", Loader.class, "DosLoader");
		check("dos-toolbox", Analyzer.class, "DosSyscallAnalyzer");
		check("retsync", Plugin.class, "RetSyncPlugin");
		check("GhidraFindcrypt", Analyzer.class, "FindCryptAnalyzer");
	}

	private void check(String extension, Class<? extends ExtensionPoint> kind, String className) {
		Set<String> found = ClassSearcher.getClasses(kind)
				.stream()
				.map(Class::getSimpleName)
				.collect(Collectors.toSet());
		String status = found.contains(className) ? "OK" : "MISSING";
		println("VERIFY " + status + " " + extension + ": " + className);
	}
}
