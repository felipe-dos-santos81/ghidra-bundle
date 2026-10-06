// Checks facts about the current program, listed one per line in an
// expectations file (see docs/superpowers/specs/2026-10-06-sanity-test-design.md).
// Usage (analyzeHeadless): -postScript SanityCheck.java <expectations file> <output dir>
// Prints "SANITY PASS <fact>" or "SANITY FAIL <fact> (got ...)" per fact and
// "SANITY DONE <passed> <failed>" last; writes the decompiled C of every
// function named in a "function" fact to <output dir>/<function>.c.
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
	private DecompInterface decompiler;
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
		decompiler.openProgram(currentProgram);
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
		println("SANITY DONE " + passed + " " + failed);
	}

	private void report(String fact) {
		String problem;
		try {
			String[] t = fact.split("\\s+");
			String shape = expectedShape(t);
			problem = shape != null ? "unparseable fact (expected: " + shape + ")" : check(t);
		}
		catch (Exception e) {
			problem = e.toString();
		}
		if (problem == null) {
			passed++;
			println("SANITY PASS " + fact);
		}
		else {
			failed++;
			println("SANITY FAIL " + fact + " (got " + problem.replaceAll("\\s+", " ") + ")");
		}
	}

	/** Returns the expected shape when the fact's tokens do not fit it, else null. */
	private static String expectedShape(String[] t) {
		int n = t.length - 1;
		switch (t[0]) {
			case "loader":
				return n >= 1 ? null : "loader <name...>";
			case "block":
				return n == 2 ? null : "block <name> <start>";
			case "entry":
				return n == 1 ? null : "entry <addr>";
			case "relocations":
				return n == 2 && t[1].equals(">=") && t[2].matches("\\d+") ? null : "relocations >= <n>";
			case "bytes":
				return n == 2 ? null : "bytes <addr> <hex>";
			case "reference":
				return n == 3 && t[2].equals("->") ? null : "reference <from> -> <to>";
			case "function":
				if (n < 2) {
					return "function <f> decompiles|contains <text...>|calls <g>";
				}
				switch (t[2]) {
					case "decompiles":
						return n == 2 ? null : "function <f> decompiles";
					case "contains":
						return n >= 3 ? null : "function <f> contains <text...>";
					case "calls":
						return n == 3 ? null : "function <f> calls <g>";
					default:
						return null;
				}
			default:
				return null;
		}
	}

	/** Returns null when the fact holds, otherwise a description of what was observed. */
	private String check(String[] t) throws Exception {
		switch (t[0]) {
			case "loader": {
				String got = currentProgram.getExecutableFormat();
				return join(t, 1).equals(got) ? null : got;
			}
			case "block": {
				MemoryBlock block = currentProgram.getMemory().getBlock(t[1]);
				if (block == null) {
					return "no block named " + t[1];
				}
				return block.getStart().equals(addr(t[2])) ? null : "starts at " + block.getStart();
			}
			case "entry": {
				if (currentProgram.getSymbolTable().isExternalEntryPoint(addr(t[1]))) {
					return null;
				}
				List<String> entries = new ArrayList<>();
				currentProgram.getSymbolTable().getExternalEntryPointIterator()
						.forEachRemaining(a -> entries.add(a.toString()));
				return "entry points " + entries;
			}
			case "relocations": {
				int count = 0;
				var it = currentProgram.getRelocationTable().getRelocations();
				while (it.hasNext()) {
					it.next();
					count++;
				}
				return count >= Integer.parseInt(t[2]) ? null : count + " relocations";
			}
			case "bytes": {
				byte[] want = HexFormat.of().parseHex(t[2]);
				byte[] got = getBytes(addr(t[1]), want.length);
				return Arrays.equals(want, got) ? null : HexFormat.of().formatHex(got);
			}
			case "reference": {
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
		Function f = function(t[1]);
		if (f == null) {
			return "no function " + t[1];
		}
		String c = decompile(f);
		switch (t[2]) {
			case "decompiles":
				return c.startsWith(DECOMPILE_FAILED) ? c : null;
			case "contains": {
				if (c.startsWith(DECOMPILE_FAILED)) {
					return c;
				}
				String want = join(t, 3);
				return c.contains(want) ? null : "decompiled C without '" + want + "', see " + fileFor(f);
			}
			case "calls": {
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
		DecompileResults r = decompiler.decompileFunction(f, 60, monitor);
		if (r.failedToStart()) {
			c = DECOMPILE_FAILED + "native decompiler did not start: " + r.getErrorMessage();
		}
		else if (!r.decompileCompleted() || r.getDecompiledFunction() == null) {
			c = DECOMPILE_FAILED + r.getErrorMessage();
		}
		else {
			c = r.getDecompiledFunction().getC();
		}
		decompiled.put(f, c);
		Files.writeString(fileFor(f).toPath(), c, StandardCharsets.UTF_8);
		return c;
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
