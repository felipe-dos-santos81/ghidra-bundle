// Checks facts about the current program, listed one per line in an
// expectations file (see docs/superpowers/specs/2026-10-06-sanity-test-design.md).
// Usage (analyzeHeadless): -postScript SanityCheck.java <expectations file> <output dir>
// Prints "SANITY PASS <fact>" or "SANITY FAIL <fact> (got ...)" per fact and
// "SANITY DONE <passed> <failed>" last, and writes the same lines to
// <output dir>/results.txt when it finishes. Writes the decompiled C of every
// function named in a "decompiles" or "contains" fact to <output dir>/<function>.c.
//@category Bundle

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.mem.MemoryBlock;
import ghidra.program.model.symbol.Reference;

public class SanityCheck extends GhidraScript {

	private static final String DECOMPILE_FAILED = "DECOMPILE FAILED: ";

	private final Map<Function, String> decompiled = new HashMap<>();
	private final List<String> results = new ArrayList<>();
	private DecompInterface decompiler;
	private boolean opened;
	private File outDir;
	private int passed;
	private int failed;

	@Override
	public void run() throws Exception {
		String[] args = getScriptArgs();
		if (args.length != 2) {
			println("SANITY FAIL usage (got " + args.length + " arguments, want <expectations> <output dir>)");
			println("SANITY DONE 0 1");
			return;
		}
		outDir = new File(args[1]);
		outDir.mkdirs();
		decompiler = new DecompInterface();
		opened = decompiler.openProgram(currentProgram);
		try {
			for (String line : Files.readAllLines(new File(args[0]).toPath(), StandardCharsets.UTF_8)) {
				String fact = line.replaceFirst("#.*$", "").trim();
				if (!fact.isEmpty()) {
					report(fact);
				}
			}
		}
		finally {
			decompiler.dispose();
		}
		emit("SANITY DONE " + passed + " " + failed);
		Files.write(new File(outDir, "results.txt").toPath(), results, StandardCharsets.UTF_8);
	}

	private void emit(String line) {
		println(line);
		results.add(line);
	}

	private void report(String fact) {
		String problem;
		try {
			problem = check(fact.split("\\s+"));
		}
		catch (Unparseable e) {
			problem = "unparseable fact (expected: " + e.getMessage() + ")";
		}
		catch (Exception e) {
			problem = e.toString();
		}
		if (problem == null) {
			passed++;
			emit("SANITY PASS " + fact);
		}
		else {
			failed++;
			emit("SANITY FAIL " + fact + " (got " + problem.replaceAll("\\s+", " ") + ")");
		}
	}

	/** Thrown by {@link #need} when a fact's tokens do not fit its shape. */
	private static final class Unparseable extends RuntimeException {
		Unparseable(String shape) {
			super(shape);
		}
	}

	private static void need(boolean ok, String shape) {
		if (!ok) {
			throw new Unparseable(shape);
		}
	}

	/** Returns null when the fact holds, otherwise a description of what was observed. */
	private String check(String[] t) throws Exception {
		switch (t[0]) {
			case "loader": {
				need(t.length >= 2, "loader <name...>");
				String got = currentProgram.getExecutableFormat();
				return join(t, 1).equals(got) ? null : got;
			}
			case "block": {
				need(t.length == 3, "block <name> <start>");
				MemoryBlock block = getMemoryBlock(t[1]);
				if (block == null) {
					return "no block named " + t[1];
				}
				return block.getStart().equals(addr(t[2])) ? null : "starts at " + block.getStart();
			}
			case "entry": {
				need(t.length == 2, "entry <addr>");
				if (currentProgram.getSymbolTable().isExternalEntryPoint(addr(t[1]))) {
					return null;
				}
				List<String> entries = new ArrayList<>();
				currentProgram.getSymbolTable().getExternalEntryPointIterator()
						.forEachRemaining(a -> entries.add(a.toString()));
				return "entry points " + entries;
			}
			case "relocations": {
				need(t.length == 3 && t[1].equals(">=") && t[2].matches("\\d+"), "relocations >= <n>");
				int count = currentProgram.getRelocationTable().getSize();
				return count >= Integer.parseInt(t[2]) ? null : count + " relocations";
			}
			case "bytes": {
				need(t.length == 3, "bytes <addr> <hex>");
				byte[] want = HexFormat.of().parseHex(t[2]);
				byte[] got = getBytes(addr(t[1]), want.length);
				return Arrays.equals(want, got) ? null : HexFormat.of().formatHex(got);
			}
			case "reference": {
				need(t.length == 4 && t[2].equals("->"), "reference <from> -> <to>");
				Address to = addr(t[3]);
				Reference[] refs = getReferencesFrom(addr(t[1]));
				for (Reference ref : refs) {
					if (ref.getToAddress().equals(to)) {
						return null;
					}
				}
				return "references " + Arrays.toString(refs);
			}
			case "function":
				return checkFunction(t);
			default:
				return "unknown fact type '" + t[0] + "'";
		}
	}

	private String checkFunction(String[] t) throws Exception {
		need(t.length >= 3, "function <f> decompiles|contains <text...>|calls <g>");
		Function f = function(t[1]);
		if (f == null) {
			return "no function " + t[1];
		}
		switch (t[2]) {
			case "decompiles": {
				need(t.length == 3, "function <f> decompiles");
				String c = decompile(f);
				return c.startsWith(DECOMPILE_FAILED) ? c : null;
			}
			case "contains": {
				need(t.length >= 4, "function <f> contains <text...>");
				String c = decompile(f);
				if (c.startsWith(DECOMPILE_FAILED)) {
					return c;
				}
				String want = join(t, 3);
				return c.contains(want) ? null : "decompiled C without '" + want + "', see " + fileFor(f);
			}
			case "calls": {
				need(t.length == 4, "function <f> calls <g>");
				Function callee = function(t[3]);
				if (callee == null) {
					return "no function " + t[3];
				}
				var called = f.getCalledFunctions(monitor);
				return called.contains(callee) ? null : "calls " + called;
			}
			default:
				return "unknown function check '" + t[2] + "'";
		}
	}

	private String decompile(Function f) throws Exception {
		String c = decompiled.get(f);
		if (c != null) {
			return c;
		}
		if (!opened) {
			c = notStarted(null);
		}
		else {
			DecompileResults r = decompiler.decompileFunction(f, 60, monitor);
			if (r.failedToStart()) {
				c = notStarted(r.getErrorMessage());
			}
			else if (!r.decompileCompleted() || r.getDecompiledFunction() == null) {
				c = DECOMPILE_FAILED + reason(r.getErrorMessage());
			}
			else {
				c = r.getDecompiledFunction().getC();
			}
		}
		decompiled.put(f, c);
		Files.writeString(fileFor(f).toPath(), c, StandardCharsets.UTF_8);
		return c;
	}

	private String notStarted(String message) {
		return DECOMPILE_FAILED + "native decompiler did not start: " + reason(message);
	}

	/** The decompiler's own message, else its last message, else a placeholder; never empty. */
	private String reason(String message) {
		if (message == null || message.isBlank()) {
			message = decompiler.getLastMessage();
		}
		return message == null || message.isBlank() ? "no message from the decompiler" : message;
	}

	private File fileFor(Function f) {
		return new File(outDir, f.getName().replaceAll("[^A-Za-z0-9_.-]", "_") + ".c");
	}

	/** A function by global name, else by address. */
	private Function function(String nameOrAddress) {
		List<Function> byName = getGlobalFunctions(nameOrAddress);
		if (!byName.isEmpty()) {
			return byName.get(0);
		}
		Address a = currentProgram.getAddressFactory().getAddress(nameOrAddress);
		return a == null ? null : getFunctionAt(a);
	}

	/** Parses "00010000" (default space) or "1000:0001" (segmented). */
	private Address addr(String text) {
		Address a = currentProgram.getAddressFactory().getAddress(text);
		if (a == null) {
			throw new IllegalArgumentException("bad address '" + text + "'");
		}
		return a;
	}

	private static String join(String[] t, int from) {
		return String.join(" ", Arrays.copyOfRange(t, from, t.length));
	}
}
