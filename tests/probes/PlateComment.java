// Seeds or prints a function's plate comment, for checking LLM4DecompileRefine.java's
// comment handling. Arguments: <function name> seed|print. "seed" sets the plate comment
// to a user note followed by a stale LLM4Decompile block from another model; "print"
// prints it between "PLATE BEGIN" and "PLATE END" lines.
//@category Bundle

import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.CommentType;
import ghidra.program.model.listing.Function;

public class PlateComment extends GhidraScript {

	static final String SEED = "user note\n\n--- LLM4Decompile (old-model) ---\nold junk";

	@Override
	public void run() throws Exception {
		String[] args = getScriptArgs();
		Function f = getFunction(args[0]);
		if (f == null) {
			throw new IllegalArgumentException("no function " + args[0]);
		}
		if (args[1].equals("seed")) {
			currentProgram.getListing().setComment(f.getEntryPoint(), CommentType.PLATE, SEED);
			println("PLATE SEEDED");
		}
		else {
			println("PLATE BEGIN\n" + currentProgram.getListing().getComment(CommentType.PLATE, f.getEntryPoint()) +
				"\nPLATE END");
		}
	}
}
