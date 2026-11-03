// Refines one function's decompiled pseudo-C into readable C with an LLM4Decompile-Ref
// model (github.com/albertan017/LLM4Decompile) served by Ollama, and writes the result
// into the function's plate comment below a marker line (replacing an earlier block).
//
// Target: the function containing the cursor in the GUI; headlessly, the first script
// argument (a function name or address). Console lines: "LLM4DECOMPILE OK <function>
// <chars> chars" followed by the C, "LLM4DECOMPILE WARN ...", "LLM4DECOMPILE REPLACED",
// "LLM4DECOMPILE FAIL <reason>".
//
// Model and server: environment variables LLM4DECOMPILE_MODEL and LLM4DECOMPILE_URL win;
// else llm4decompile.properties (model=, url=) in the installed LLM4Decompile extension
// (Ghidra/Extensions/LLM4Decompile/), or two directories above this file when run from a
// checkout; else the defaults below.
//@category LLM4Decompile

import java.io.IOException;
import java.io.InputStream;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Properties;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutionException;

import com.google.gson.Gson;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import generic.jar.ResourceFile;
import ghidra.framework.Application;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.CommentType;
import ghidra.program.model.listing.Function;
import ghidra.util.exception.CancelledException;

public class LLM4DecompileRefine extends GhidraScript {

	private static final String DEFAULT_MODEL = "hf.co/mradermacher/llm4decompile-9b-v2-GGUF:Q8_0";
	private static final String DEFAULT_URL = "http://127.0.0.1:11434";
	private static final String PROPERTIES = "llm4decompile.properties";
	private static final String MARKER_PREFIX = "--- LLM4Decompile (";
	// The V2 models were trained on exactly this framing of Ghidra's output.
	private static final String PROMPT_BEFORE = "# This is the assembly code:\n";
	private static final String PROMPT_AFTER = "\n# What is the source code?\n";
	// The model's context is 4096 tokens; a longer prompt leaves no room for the answer.
	private static final int PROMPT_CHAR_BUDGET = 6000;

	@Override
	public void run() throws Exception {
		Function function = target();
		monitor.checkCancelled();
		String pseudoC = decompile(function);
		monitor.checkCancelled();
		String[] config = config();
		String model = config[0];
		String refined = refine(config[1], model, pseudoC);
		monitor.checkCancelled();
		writeComment(function, model, refined);
		println("LLM4DECOMPILE OK " + function.getName() + " " + refined.length() + " chars");
		println(refined);
	}

	private Function target() throws Exception {
		String[] args = getScriptArgs();
		if (args.length > 0) {
			Function f = getFunction(args[0]);
			if (f == null) {
				Address addr = toAddr(args[0]);
				f = addr == null ? null : getFunctionAt(addr);
			}
			if (f == null) {
				fail("no function " + args[0]);
			}
			return f;
		}
		Function f = currentAddress == null ? null : getFunctionContaining(currentAddress);
		if (f == null) {
			fail("no function at " + currentAddress + " (put the cursor inside a function)");
		}
		return f;
	}

	private String decompile(Function f) throws Exception {
		DecompInterface decomp = new DecompInterface();
		try {
			decomp.openProgram(currentProgram);
			DecompileResults res = decomp.decompileFunction(f, 60, monitor);
			if (res == null || !res.decompileCompleted() || res.getDecompiledFunction() == null) {
				fail("decompiler: " + (res == null ? "no result" : res.getErrorMessage()));
			}
			return res.getDecompiledFunction().getC();
		}
		finally {
			decomp.dispose();
		}
	}

	private String[] config() {
		String model = System.getenv("LLM4DECOMPILE_MODEL");
		String url = System.getenv("LLM4DECOMPILE_URL");
		if (model == null || url == null) {
			Properties props = new Properties();
			ResourceFile file = new ResourceFile(Application.getInstallationDirectory(),
				"Ghidra/Extensions/LLM4Decompile/" + PROPERTIES);
			if (!file.isFile() && getSourceFile() != null && getSourceFile().getParentFile() != null &&
				getSourceFile().getParentFile().getParentFile() != null) {
				file = new ResourceFile(getSourceFile().getParentFile().getParentFile(), PROPERTIES);
			}
			if (file.isFile()) {
				try (InputStream in = file.getInputStream()) {
					props.load(in);
				}
				catch (IOException e) {
					println("LLM4DECOMPILE WARN cannot read " + file + ": " + e.getMessage());
				}
			}
			if (model == null) {
				model = props.getProperty("model", DEFAULT_MODEL);
			}
			if (url == null) {
				url = props.getProperty("url", DEFAULT_URL);
			}
		}
		return new String[] { model.trim(), url.trim().replaceAll("/+$", "") };
	}

	private String refine(String url, String model, String pseudoC) throws Exception {
		if (pseudoC.length() > PROMPT_CHAR_BUDGET) {
			println("LLM4DECOMPILE WARN pseudo-C is " + pseudoC.length() +
				" chars; the model's 4096-token context may truncate the answer");
		}
		Map<String, Object> options = new LinkedHashMap<>();
		options.put("temperature", 0);
		options.put("num_ctx", 4096);
		options.put("num_predict", 2048);
		Map<String, Object> body = new LinkedHashMap<>();
		body.put("model", model);
		body.put("prompt", PROMPT_BEFORE + pseudoC.strip() + PROMPT_AFTER);
		body.put("raw", true); // no chat template: this is a completion model
		body.put("stream", false);
		body.put("options", options);
		HttpRequest request = HttpRequest.newBuilder(URI.create(url + "/api/generate"))
				.timeout(Duration.ofMinutes(10))
				.header("Content-Type", "application/json")
				.POST(HttpRequest.BodyPublishers.ofString(new Gson().toJson(body), StandardCharsets.UTF_8))
				.build();
		HttpResponse<String> response;
		CompletableFuture<HttpResponse<String>> pending =
			HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build()
					.sendAsync(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
		try {
			while (!pending.isDone()) {
				if (monitor.isCancelled()) {
					pending.cancel(true);
					monitor.checkCancelled();
				}
				Thread.sleep(200);
			}
			response = pending.get();
		}
		catch (ExecutionException e) {
			fail("cannot reach " + url + ": " + e.getCause());
			return null;
		}
		catch (InterruptedException e) {
			Thread.currentThread().interrupt();
			fail("interrupted while waiting for " + url);
			return null;
		}
		if (response.statusCode() != 200) {
			fail("HTTP " + response.statusCode() + ": " + response.body());
		}
		JsonObject json = JsonParser.parseString(response.body()).getAsJsonObject();
		String text = json.has("response") ? json.get("response").getAsString().strip() : "";
		if (text.isEmpty()) {
			fail("empty response from " + model);
		}
		return text;
	}

	private void writeComment(Function f, String model, String c) {
		String marker = MARKER_PREFIX + model + ") ---";
		String existing = currentProgram.getListing().getComment(CommentType.PLATE, f.getEntryPoint());
		String kept = "";
		if (existing != null) {
			int at = existing.indexOf(MARKER_PREFIX);
			if (at >= 0) {
				kept = existing.substring(0, at).strip();
				println("LLM4DECOMPILE REPLACED");
			}
			else {
				kept = existing.strip();
			}
		}
		String text = (kept.isEmpty() ? "" : kept + "\n\n") + marker + "\n" + c;
		currentProgram.getListing().setComment(f.getEntryPoint(), CommentType.PLATE, text);
	}

	private void fail(String reason) throws Exception {
		printerr("LLM4DECOMPILE FAIL " + reason);
		// Agents (GhidraMCP runs scripts on the Swing thread) and headless runs always pass
		// a function argument; a dialog there would block until a human dismissed it.
		if (isRunningHeadless() || getScriptArgs().length > 0) {
			throw new RuntimeException(reason);
		}
		popup(reason);
		throw new CancelledException(reason);
	}
}
