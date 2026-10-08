// Exports the current program with BinExport's exporter, as BinDiff would read it.
// Prints "BINEXPORT OK <bytes>" or "BINEXPORT FAIL". Script argument: output file.
//@category Bundle

import java.io.File;

import com.google.security.binexport.BinExportExporter;

import ghidra.app.script.GhidraScript;

public class BinExportProbe extends GhidraScript {

	@Override
	public void run() throws Exception {
		File out = new File(getScriptArgs()[0]);
		boolean ok = new BinExportExporter().export(out, currentProgram,
			currentProgram.getMemory(), monitor);
		println(ok && out.length() > 0 ? "BINEXPORT OK " + out.length() : "BINEXPORT FAIL");
	}
}
