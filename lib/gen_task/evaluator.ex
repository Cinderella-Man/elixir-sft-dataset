defmodule GenTask.Evaluator do
  @moduledoc """
  Bridge to the canonical evaluator (`scripts/eval_task.exs`), run in a separate OS
  process under a wall-clock kill (see `docs/04-task-generation-loop.md` §12).

  Staging writes the in-flight triplet to a git-ignored directory **outside**
  `tasks/` so `Discovery`/`run_all`/`validate` never see it. `grade/2,3` shells out
  to the evaluator; a clean exit yields the last JSON line, a non-zero exit means the
  grade was killed/crashed (no usable JSON).
  """

  require Logger

  alias GenTask.Config

  @type grade :: {:ok, map()} | :timeout_or_crash

  @doc """
  Write `files` (a `%{relative_path => body}` map) into `dir` and return `dir`.

  Safety: refuses to write anywhere under `tasks/` — staging must target the
  git-ignored staging area, `logs/`, or a temp dir.
  """
  @spec stage!(String.t(), %{String.t() => String.t()}) :: String.t()
  def stage!(dir, files) do
    guard_not_tasks!(dir)
    File.rm_rf!(dir)
    File.mkdir_p!(dir)

    Enum.each(files, fn {rel, body} ->
      full = safe_child_path!(dir, rel)
      File.mkdir_p!(Path.dirname(full))
      File.write!(full, body)
    end)

    dir
  end

  # Join an untrusted (model-supplied) relative key onto `dir`, refusing any key
  # that resolves outside `dir`. A merged (post-repair) files map can carry a
  # `../…` key; the directory guard alone would let it escape staging into `tasks/`.
  defp safe_child_path!(dir, rel) do
    full = Path.join(dir, rel)
    expanded = Path.expand(full)
    root = Path.expand(dir)

    unless String.starts_with?(expanded, root <> "/") do
      raise ArgumentError, "unsafe file path escapes the staging dir: #{inspect(rel)}"
    end

    full
  end

  @doc """
  Grade the triplet staged in `dir` using `solution.ex`. Returns `{:ok, json}` on a
  clean run (compile-fail and test-fail both exit 0), or `:timeout_or_crash`.
  """
  @spec grade(String.t(), Config.t()) :: grade()
  def grade(dir, %Config{} = cfg), do: grade(dir, cfg, "solution.ex")

  @doc """
  Grade `dir` against an explicit `solution` (a filename inside `dir`, or a path to
  an override solution file — used by the FIM mutation gate).

  `seed` optionally overrides the evaluator's pinned ExUnit seed (`0`) via the
  `EVAL_SEED` env var read in `EvalTask.Runner` — the stability-confirmation re-grade
  (docs/12 §5.1 item 6) passes a derived nonzero seed to break the pinned test order.
  `nil` leaves the pinned `seed: 0` (byte-deterministic, the default for every gate).
  """
  @spec grade(String.t(), Config.t(), String.t(), integer() | nil) :: grade()
  def grade(dir, %Config{} = cfg, solution, seed \\ nil) do
    args = [
      "--signal=KILL",
      to_string(cfg.eval_timeout_s),
      "elixir",
      "scripts/eval_task.exs",
      dir,
      solution
    ]

    Logger.debug(
      "grade: timeout #{Enum.join(args, " ")}#{if seed, do: " (seed #{seed})", else: ""}"
    )

    case System.cmd("timeout", args, stderr_to_stdout: false, env: seed_env(seed)) do
      {out, 0} ->
        json = out |> last_json_line() |> Jason.decode!()
        Logger.debug("grade JSON: #{Jason.encode!(json)}")
        {:ok, json}

      {_out, code} ->
        Logger.debug("grade killed/crashed (exit #{code}) — no usable JSON")
        :timeout_or_crash
    end
  end

  # The environment overlay for a graded subprocess: `[{"EVAL_SEED", "<seed>"}]` when a
  # seed override is given, else `[]` (inherit the ambient environment, pinned seed `0`).
  # Public (`@doc false`) so the plumbing is unit-testable without a subprocess.
  @doc false
  @spec seed_env(integer() | nil) :: [{String.t(), String.t()}]
  def seed_env(nil), do: []
  def seed_env(seed) when is_integer(seed), do: [{"EVAL_SEED", Integer.to_string(seed)}]

  @doc "Last `{`-prefixed stdout line (mirrors `run_all.exs`)."
  @spec last_json_line(String.t()) :: String.t()
  def last_json_line(out) do
    out
    |> String.split("\n", trim: true)
    |> Enum.reverse()
    |> Enum.find("{}", &String.starts_with?(&1, "{"))
  end

  @doc """
  True when the reference passed: compiled, **at least one test actually ran and
  passed**, and no failures or errors. Accepts either a grade tuple or the decoded
  JSON map.

  `tests_passed > 0` is required — `tests_total > 0` alone is satisfiable by a
  harness whose tests are all excluded or `@tag :skip` (docs/05 #19, demonstrated
  in `docs/prototypes/proto_vacuous_green.exs`).
  """
  @spec green?(grade() | map()) :: boolean()
  def green?(:timeout_or_crash), do: false
  def green?({:ok, json}), do: green?(json)

  def green?(%{} = json) do
    json["compiled"] == true and
      (json["tests_total"] || 0) > 0 and
      (json["tests_passed"] || 0) > 0 and
      (json["tests_failed"] || 0) == 0 and
      (json["tests_errors"] || 0) == 0
  end

  @doc """
  True when a mutant's grade proves the harness **exercised** the mutation: the
  mutant compiled and at least one test ran and failed.

  This is deliberately stricter than `not green?/1`: a mutant that fails to
  compile, a harness that fails to load against it, or an eval timeout are all
  non-green without the harness ever observing the mutated behavior — counting
  those as kills lets a vacuous harness through the mutation gate (docs/05 #18).
  """
  @spec killed_by_tests?(grade() | map()) :: boolean()
  def killed_by_tests?(:timeout_or_crash), do: false
  def killed_by_tests?({:ok, json}), do: killed_by_tests?(json)

  def killed_by_tests?(%{} = json) do
    json["compiled"] == true and (json["tests_failed"] || 0) > 0
  end

  @doc """
  True when a mutant's grade shows the harness ERRORED against it while the mutant
  itself compiled: load-time raise (a gutted `defmacro` blowing up harness
  compilation), a `setup` crash, an exit mid-test.

  On its own this is NOT proof of coverage — that is `killed_by_tests?/1`'s bar
  (docs/05 #18). But every mutation gate runs only after the same harness graded
  green against the reference, and under that precondition an error appearing only
  against the mutant is CAUSED by the mutation and is a kill — the argument
  `scripts/validate.exs --mutants` already encodes (docs/10 §5.1, the 074 macro
  family). Callers must ensure reference-green before treating this as a kill.
  """
  @spec errored_against_mutant?(grade() | map()) :: boolean()
  def errored_against_mutant?(:timeout_or_crash), do: false
  def errored_against_mutant?({:ok, json}), do: errored_against_mutant?(json)

  def errored_against_mutant?(%{} = json) do
    json["compiled"] == true and (json["tests_errors"] || 0) > 0
  end

  @doc """
  House-style / warning / harness-standard shortfall for a **green** base/variation
  grade, or `nil` when the solution already meets the bar. Used by the quality gate
  (`GenTask.Cycle`): a green, mutant-killing solution should still carry a `@moduledoc`,
  at least one `@spec` and `@doc`, no `TODO`, stay within 98 columns, avoid
  SQL-interpolation, and compile with zero warnings — every check the analysis rubric
  scores, so an accepted reference banks the full analysis subscore.

  Two further gates use the `files` (the accepted triplet) when supplied (docs/12 §5.1):

    * **minimum test-count floor** (item 3) — `tests_total >= max(3, public_fn_count)`;
      both numbers are already in the grade JSON.
    * **harness anti-pattern lint (S9)** (item 2) — the four detector families ported
      from `scripts/lint_harnesses.exs`. `:sys.get_state`/`replace_state`,
      `assert inspect(...)`, and exact `assert_raise Mod, "msg"` pins are HARD
      shortfalls; an undocumented `:infinity` interval option or an undocumented
      `:cleanup`/`:sweep`/`:tick` trigger send is a documents-or-removes advisory that
      fires only when `prompt.md` does not document it.

  Returns a `; `-joined description of every shortfall. `files` defaults to `%{}`, in
  which case only the grade-JSON checks run (the harness/prompt checks need the text).
  """
  @spec quality_shortfall(map(), %{optional(String.t()) => String.t()}) :: String.t() | nil
  def quality_shortfall(%{} = json, files \\ %{}) do
    a = json["analysis"] || %{}
    warnings = json["compile_warnings"] || 0
    tests_total = json["tests_total"] || 0
    public_fns = a["public_fn_count"] || 0
    floor = max(3, public_fns)
    harness = files["test_harness.exs"] || ""
    prompt = files["prompt.md"] || ""

    []
    |> add_if(warnings > 0, "#{warnings} compile warning(s) — silence them")
    |> add_if(a["has_moduledoc"] != true, "no @moduledoc")
    |> add_if(a["has_typespecs"] != true, "no @spec on any public function")
    |> add_if(a["has_doc_on_public_fns"] != true, "no @doc on any public function")
    |> add_if((a["todo_count"] || 0) > 0, "#{a["todo_count"]} TODO/FIXME marker(s) in the code")
    |> add_if(
      (a["lines_over_98"] || 0) > 0,
      "#{a["lines_over_98"]} line(s) over 98 columns — wrap them"
    )
    |> add_if(
      a["sql_injection_risk"] == true,
      "string interpolation inside SQL — use parameterized queries"
    )
    |> add_if(
      tests_total < floor,
      "only #{tests_total} test(s) — the harness needs at least #{floor} " <>
        "(max of 3 and the #{public_fns} public function(s))"
    )
    |> add_harness_shortfalls(harness, prompt)
    |> case do
      [] -> nil
      reasons -> reasons |> Enum.reverse() |> Enum.join("; ")
    end
  end

  defp add_if(list, true, msg), do: [msg | list]
  defp add_if(list, false, _msg), do: list

  @doc """
  Number of compile warnings in a `grade` (0 for a timeout/crash). Used by the
  derivative accept sites (fim/wt_/tfim) to gate zero-warnings without reusing the full
  house-style check — the inherited parent `solution.ex` would misfire `@moduledoc`/
  `@spec` checks there (docs/12 §5.1 item 1).
  """
  @spec compile_warnings(grade() | map()) :: non_neg_integer()
  def compile_warnings(:timeout_or_crash), do: 0
  def compile_warnings({:ok, json}), do: compile_warnings(json)
  def compile_warnings(%{} = json), do: json["compile_warnings"] || 0

  # ── S9 harness anti-pattern detectors (ported from scripts/lint_harnesses.exs) ──

  @trigger_atoms ~w(cleanup sweep tick)

  # No harness text (e.g. quality_shortfall called with only the grade JSON) → skip.
  defp add_harness_shortfalls(list, "", _prompt), do: list

  defp add_harness_shortfalls(list, harness, prompt) do
    sys = count(harness, ~r/:sys\.(get_state|replace_state)/)
    insp = count(harness, ~r/assert\s+inspect\(/)
    exact_raise = count(harness, ~r/assert_raise\s+[\w.]+,\s*"/)
    infinity = undocumented_infinity_keys(harness, prompt)
    triggers = undocumented_trigger_atoms(harness, prompt)

    list
    # HARD shortfalls — the anti-pattern must go (the fixer reworks the harness).
    |> add_if(
      sys > 0,
      "test_harness.exs reaches into internal state via `:sys.get_state`/`:sys.replace_state` " <>
        "(#{sys} call(s)) — assert observable behavior through the public API instead"
    )
    |> add_if(
      insp > 0,
      "test_harness.exs uses `assert inspect(...)` (#{insp}) — assert the value or structure " <>
        "directly, not its `inspect` string form (brittle to formatting)"
    )
    |> add_if(
      exact_raise > 0,
      "test_harness.exs pins an exact exception message in `assert_raise Mod, \"…\"` " <>
        "(#{exact_raise}) — assert the exception TYPE only, not the message text"
    )
    # Documents-or-removes advisories — fire only when the prompt does not document
    # them. The repair contract forbids prompt.md edits, so in-loop the reachable fix
    # is removing the hidden dependency; an author who WANTS the contract must write it
    # into prompt.md before generation (the detector then stays silent).
    |> add_if(
      infinity != [],
      "test_harness.exs relies on `:infinity` for the interval option(s) " <>
        "#{Enum.join(infinity, ", ")}, a behavior prompt.md never documents — rework the " <>
        "harness so it does not depend on that hidden contract (use a real interval or a " <>
        "documented seam); prompt.md may not be edited during repair"
    )
    |> add_if(
      triggers != [],
      "test_harness.exs sends the undocumented trigger message(s) " <>
        "#{Enum.map_join(triggers, ", ", &":#{&1}")} to the server, which prompt.md never " <>
        "documents — rework the harness to drive that behavior through the documented " <>
        "public API instead; prompt.md may not be edited during repair"
    )
  end

  defp count(harness, re), do: length(Regex.scan(re, harness))

  # Interval-style option keys passed as `:infinity` that the prompt never mentions.
  # Narrow key shape (interval/period/_ms) so a legitimate `timeout: :infinity` or
  # `max_uses: :infinity` — different semantics — is not misflagged.
  defp undocumented_infinity_keys(harness, prompt) do
    if String.contains?(prompt, ":infinity") do
      []
    else
      ~r/(\w*(?:interval|period)\w*|\w+_ms):\s*:infinity/
      |> Regex.scan(harness, capture: :all_but_first)
      |> List.flatten()
      |> Enum.uniq()
    end
  end

  # Periodic-action trigger messages sent to the server while the prompt never documents
  # the message. The `\b` after the atom matters: a bare `:cleanup` substring inside the
  # OPTION name `:cleanup_interval_ms` does not document the MESSAGE.
  defp undocumented_trigger_atoms(harness, prompt) do
    ~r/send\(\s*\w+,\s*:(#{Enum.join(@trigger_atoms, "|")})\s*\)/
    |> Regex.scan(harness, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.reject(&Regex.match?(~r/:#{&1}\b/, prompt))
  end

  @doc """
  Canonically format the stageable pair of a triplet — `solution.ex` (plain module
  or `<file>` bundle, per part) and `test_harness.exs` — with `Code.format_string!/1`.

  Runs BEFORE grading (see `GenTask.Cycle.run/3`) so accepted bytes are
  formatter-canonical under the pinned toolchain (docs/10 R6) and the graded bytes
  are exactly the promoted bytes. A file that does not parse is left unchanged: the
  compile gate then reports it with real diagnostics instead of a formatter raise
  here. Other keys (`prompt.md`, …) pass through untouched.
  """
  @spec autoformat(%{String.t() => String.t()}) :: %{String.t() => String.t()}
  def autoformat(%{} = files) do
    Map.new(files, fn
      {name, body} when name in ["solution.ex", "test_harness.exs"] and is_binary(body) ->
        {name, autoformat_body(body)}

      other ->
        other
    end)
  end

  @bundle_block ~r/(<file path="[^"]+">\n)(.*?)(\n<\/file>)/s

  defp autoformat_body(body) do
    if String.contains?(body, "<file path=") do
      formatted =
        Regex.replace(@bundle_block, body, fn whole, open, part, close ->
          if Regex.match?(~r/path="[^"]+\.exs?"/, open) do
            open <> format_or_keep(part, false) <> close
          else
            whole
          end
        end)

      String.trim_trailing(formatted, "\n") <> "\n"
    else
      format_or_keep(body, true)
    end
  end

  # Formats `src`; returns it unchanged when it does not parse. Whole files always
  # end with exactly one newline (the `mix format` convention); bundle parts are
  # re-embedded bare.
  defp format_or_keep(src, newline?) do
    formatted =
      src |> Code.format_string!() |> IO.iodata_to_binary() |> String.trim_trailing("\n")

    if newline?, do: formatted <> "\n", else: formatted
  rescue
    _ -> src
  end

  @doc """
  Human-readable repair feedback for a failed cycle. Handles a timeout/crash, a
  vacuous harness (the mutant survived), a house-style/warning shortfall, and ordinary
  compile/test failures.
  """
  @spec repair_report(
          :timeout_or_crash
          | {:vacuous, String.t()}
          | {:quality, String.t()}
          | {:warnings, non_neg_integer()}
          | {:flaky, integer()}
          | {:failed, grade()}
        ) :: String.t()
  def repair_report(:timeout_or_crash) do
    "The evaluation timed out or crashed (likely an infinite loop or a process that " <>
      "never returns). Ensure every code path terminates and the harness does not block."
  end

  def repair_report({:vacuous, why}) do
    "Mutation gate failed: #{why}. Strengthen test_harness.exs so it fails when that " <>
      "code is gutted (add assertions that actually exercise the behavior) — do not " <>
      "weaken the implementation."
  end

  def repair_report({:quality, shortfall}) do
    "The files graded green but fall short of the house style / harness standard: " <>
      "#{shortfall}. Fix solution.ex and/or test_harness.exs to resolve every point above — " <>
      "keep the module's behavior correct, keep ALL tests (do not delete any), and do not " <>
      "weaken what the tests verify. When a harness assertion is the problem, rewrite it to " <>
      "check observable behavior; do not remove coverage."
  end

  def repair_report({:warnings, n}) do
    "The files graded green but compile with #{n} warning(s). Silence every warning " <>
      "(prefix unused variables with `_`, match float zero as `+0.0`/`-0.0`, drop " <>
      "unreachable clauses) without changing behavior or weakening test_harness.exs."
  end

  def repair_report({:flaky, seed}) do
    "The files graded green on the pinned test order but FAILED a re-run with ExUnit " <>
      "seed #{seed} (a different test order). That is order-dependence or timing " <>
      "sensitivity — make every test independent of run order (fresh state per test, a " <>
      "fake clock instead of real sleeps, unique names/ids) so the harness passes at any seed."
  end

  def repair_report({:failed, :timeout_or_crash}), do: repair_report(:timeout_or_crash)

  def repair_report({:failed, {:ok, json}}), do: report_from_json(json)

  defp report_from_json(json) do
    compile_errors = json["compile_errors"] || []
    test_failures = json["test_failures"] || []

    cond do
      json["compiled"] != true and compile_errors != [] ->
        "Compilation failed:\n" <>
          Enum.map_join(compile_errors, "\n", fn e ->
            "  - #{e["type"]}: #{e["message"]}"
          end)

      test_failures != [] ->
        "Tests failed (#{json["tests_failed"]} failed, #{json["tests_errors"]} errors):\n" <>
          Enum.map_join(test_failures, "\n", fn f ->
            "  - #{f["test"]} (#{f["module"]}): #{f["message"]}"
          end)

      json["compiled"] != true ->
        "Compilation failed (no diagnostics captured)."

      true ->
        # Reachable e.g. when no test actually ran and passed (all @tag :skip /
        # excluded) — say so explicitly, or the fixer sees only zeros and cannot
        # tell what to repair.
        "The reference did not pass: compiled=#{json["compiled"]}, " <>
          "tests_total=#{json["tests_total"]}, tests_passed=#{json["tests_passed"]}, " <>
          "tests_failed=#{json["tests_failed"]}, tests_errors=#{json["tests_errors"]}, " <>
          "tests_skipped=#{json["tests_skipped"]}, tests_excluded=#{json["tests_excluded"]}. " <>
          "At least one test must RUN and pass — remove @tag :skip / excluded tags " <>
          "or fix the harness so its tests execute."
    end
  end

  defp guard_not_tasks!(dir) do
    normalized = Path.expand(dir)
    tasks_root = Path.expand("tasks")

    if normalized == tasks_root or String.starts_with?(normalized, tasks_root <> "/") do
      raise ArgumentError,
            "refusing to stage into the protected tasks/ tree: #{dir} (#{normalized})"
    end
  end
end
