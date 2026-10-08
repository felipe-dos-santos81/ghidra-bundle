// Prints where GhidrAssist and RevEng.AI keep their files by default, one line each:
// "PORTABLE OK|OUTSIDE|MISSING <label>: <path>". OK means inside Ghidra's user settings
// directory, which the bundle's portable mode puts under dist/.../portable/settings.
// Script arguments: extension directory names to check (GhidrAssist, plugin-ghidra);
// none checks both.
//@category Bundle

import java.lang.reflect.Field;
import java.nio.file.Path;
import java.util.List;
import java.util.concurrent.Callable;

import ghidra.app.script.GhidraScript;
import ghidra.framework.Application;

public class PortablePaths extends GhidraScript {

	private Path settings;

	@Override
	public void run() throws Exception {
		settings = Application.getUserSettingsDirectory().toPath().toAbsolutePath().normalize();
		List<String> wanted = List.of(getScriptArgs());
		if (wanted.isEmpty() || wanted.contains("GhidrAssist")) {
			check("GhidrAssist Lucene index", () -> {
				Class<?> os = Class.forName("ghidrassist.GAUtils$OperatingSystem");
				Object current = os.getMethod("detect").invoke(null);
				return Class.forName("ghidrassist.GAUtils")
						.getMethod("getDefaultLucenePath", os)
						.invoke(null, current);
			});
			check("GhidrAssist analysis DB", () -> staticField("ghidrassist.AnalysisDB", "DEFAULT_DB_PATH"));
			check("GhidrAssist RLHF DB", () -> staticField("ghidrassist.RLHFDatabase", "DEFAULT_DB_PATH"));
		}
		if (wanted.isEmpty() || wanted.contains("plugin-ghidra")) {
			check("RevEng.AI config", () -> staticField(
				"ai.reveng.toolkit.ghidra.plugins.ReaiPluginPackage", "DEFAULT_CONFIG_PATH"));
		}
	}

	private static Object staticField(String className, String name) throws Exception {
		Field field = Class.forName(className).getDeclaredField(name);
		field.setAccessible(true);
		return field.get(null);
	}

	private void check(String label, Callable<Object> source) {
		try {
			Path path = Path.of(String.valueOf(source.call())).toAbsolutePath().normalize();
			println("PORTABLE " + (path.startsWith(settings) ? "OK" : "OUTSIDE") + " " + label + ": " + path);
		}
		catch (Exception | LinkageError e) {
			println("PORTABLE MISSING " + label + ": " + e);
		}
	}
}
