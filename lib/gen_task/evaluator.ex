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
  True when the reference passed: compiled, at least one test, and no failures or
  errors. Accepts either a grade tuple or the decoded JSON map.
  """
  @spec green?(grade() | map()) :: boolean()
  def green?(:timeout_or_crash), do: false
  def green?({:ok, json}), do: green?(json)

  def green?(%{} = json) do
    json["compiled"] == true and
      (json["tests_total"] || 0) > 0 and
      (json["tests_failed"] || 0) == 0 and
      (json["tests_errors"] || 0) == 0
  end

  @doc """
  Human-readable repair feedback for a failed cycle. Handles a timeout/crash, a
  vacuous harness (the mutant survived), and ordinary compile/test failures.
  """
  @spec repair_report(:timeout_or_crash | {:vacuous, grade()} | {:failed, grade()}) ::
          String.t()
  def repair_report(:timeout_or_crash) do
    "The evaluation timed out or crashed (likely an infinite loop or a process that " <>
      "never returns). Ensure every code path terminates and the harness does not block."
  end

  def repair_report({:vacuous, _grade}) do
    "The tests still PASS even after every function body in solution.ex is replaced by " <>
      "`raise` (mutation gate). This means the harness is vacuous — it does not actually " <>
      "exercise the behavior. Strengthen test_harness.exs so it fails when the " <>
      "implementation is gutted."
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
        "The reference did not pass: " <>
          "compiled=#{json["compiled"]}, tests_total=#{json["tests_total"]}, " <>
          "tests_failed=#{json["tests_failed"]}, tests_errors=#{json["tests_errors"]}."
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
