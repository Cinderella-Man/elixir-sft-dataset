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
  """
  @spec grade(String.t(), Config.t(), String.t()) :: grade()
  def grade(dir, %Config{} = cfg, solution) do
    args = [
      "--signal=KILL",
      to_string(cfg.eval_timeout_s),
      "elixir",
      "scripts/eval_task.exs",
      dir,
      solution
    ]

    Logger.debug("grade: timeout #{Enum.join(args, " ")}")

    case System.cmd("timeout", args, stderr_to_stdout: false) do
      {out, 0} ->
        json = out |> last_json_line() |> Jason.decode!()
        Logger.debug("grade JSON: #{Jason.encode!(json)}")
        {:ok, json}

      {_out, code} ->
        Logger.debug("grade killed/crashed (exit #{code}) — no usable JSON")
        :timeout_or_crash
    end
  end

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
  House-style / warning shortfall for a **green** base/variation grade, or `nil` when
  the solution already meets the bar. Used by the quality gate (`GenTask.Cycle`): a
  green, mutant-killing solution should still carry a `@moduledoc`, at least one
  `@spec` and `@doc`, no `TODO`, stay within 98 columns, avoid SQL-interpolation, and
  compile with zero warnings — every check the analysis rubric scores, so an accepted
  reference banks the full analysis subscore. Returns a `; `-joined description of
  every shortfall.
  """
  @spec quality_shortfall(map()) :: String.t() | nil
  def quality_shortfall(%{} = json) do
    a = json["analysis"] || %{}
    warnings = json["compile_warnings"] || 0

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
    |> case do
      [] -> nil
      reasons -> reasons |> Enum.reverse() |> Enum.join("; ")
    end
  end

  defp add_if(list, true, msg), do: [msg | list]
  defp add_if(list, false, _msg), do: list

  @doc """
  Human-readable repair feedback for a failed cycle. Handles a timeout/crash, a
  vacuous harness (the mutant survived), a house-style/warning shortfall, and ordinary
  compile/test failures.
  """
  @spec repair_report(
          :timeout_or_crash
          | {:vacuous, String.t()}
          | {:quality, String.t()}
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
    "The solution is green but does not meet the house style: #{shortfall}. Fix " <>
      "solution.ex so it has a `@moduledoc`, an `@spec` and `@doc` on public functions, " <>
      "no `TODO` markers, and compiles with ZERO warnings. Keep the behavior identical " <>
      "and do not weaken test_harness.exs."
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
