#!/usr/bin/env elixir
# validate.exs — Quality gate for the task corpus.
#
# DEFAULT: perfect-score — every reference solution must grade a perfect overall of
# 1.0 (compiles with ZERO warnings, all tests pass, and full analysis: @moduledoc +
# @spec + @doc, no >98-char lines, no TODO/FIXME, no SQLi pattern). The gate checks
# the RAW invariants (0 failed, 0 errors, ≥1 passed, 0 warnings), not the rounded
# overall — a 139/140 harness rounds to 1.0 but is not perfect. Reports the exact
# deductions per task and writes them to results/perfect_failures.txt.
#
# Every task dir must also be classifiable and carry its solution: missing or
# unclassifiable dirs are reported as failures, never silently skipped.
#
# Opt-in lighter checks:
#   --green       reference-green only (compiles + tests pass; ignores analysis/warnings)
#   --fim         FIM mutation only (a raise-body mutant must make the parent harness fail)
#   --mutants     whole-solution mutation for :single/:multifile/:write_test — a mutant
#                 with every function body replaced by `raise` must make the harness
#                 FAIL (tfim is skipped: its non-vacuousness gate runs at mint time)
#   --stability N flake filter must see N consecutive serial passes to recover a
#                 test-failure suspect (default 1). Recovered flakes are always
#                 appended to logs/flaky.jsonl — a repeat offender there needs fixing.
#   --semantic-mutants  REPORT-ONLY assertion-tightness measurement: first-order
#                 semantic mutants (comparison swap, ±1, :ok↔:error, bool flip) of
#                 the reference; per-task kill-rate + corpus histogram + weakest 20;
#                 ledger logs/semantic_mutants.jsonl. ≤ --sm-limit (40) evals/task —
#                 EXPENSIVE; scope with --only for spot checks.
#
# Every eval subprocess runs under `timeout --signal=KILL` (EVAL_TIMEOUT_S, default
# 240s) so one hanging solution cannot stall the sweep.
#
# Concurrency defaults to min(16, schedulers-2); override with EVAL_CONCURRENCY=N.
#
# Usage: elixir scripts/validate.exs [--green] [--fim] [--mutants] [--stability N]

for pattern <- ["_build/dev/lib/*/ebin", "_build/test/lib/*/ebin"],
    path <- Path.wildcard(pattern) do
  Code.prepend_path(path)
end

defmodule Validate do
  @moduledoc false

  def main(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          green: :boolean,
          fim: :boolean,
          mutants: :boolean,
          semantic_mutants: :boolean,
          sm_limit: :integer,
          stability: :integer,
          only: :string
        ]
      )

    discovered = EvalTask.Discovery.all()
    {tasks, corpus_failures} = split_corpus(discovered, opts[:only])
    IO.puts("Concurrency: #{concurrency()} (EVAL_CONCURRENCY to override)")
    report("corpus-integrity", corpus_failures)

    cond do
      opts[:green] ->
        f = corpus_failures ++ reference_green(tasks)
        IO.puts("\n=== VALIDATION SUMMARY ===")
        report("reference-green", f)
        finish(f == [], "ALL GREEN ✓")

      opts[:fim] ->
        f = corpus_failures ++ fim_mutation(tasks)
        IO.puts("\n=== VALIDATION SUMMARY ===")
        report("fim-mutation", f)
        finish(f == [], "ALL FIM TARGETS EXERCISED ✓")

      opts[:mutants] ->
        f = corpus_failures ++ whole_mutation(tasks)
        IO.puts("\n=== VALIDATION SUMMARY ===")
        report("whole-mutation", f)
        finish(f == [], "ALL HARNESSES KILL THEIR MUTANT ✓")

      opts[:semantic_mutants] ->
        semantic_report(tasks, opts[:sm_limit] || 40)
        finish(true, "SEMANTIC-MUTANT REPORT COMPLETE (report-only — no gate)")

      true ->
        failures = corpus_failures ++ perfect_score(tasks, opts[:stability] || 1)
        IO.puts("\n=== VALIDATION SUMMARY ===")
        report("perfect-score", failures)
        persist_failures(failures)
        finish(failures == [], "ALL PERFECT ✓ (every task scores 1.0)")
    end
  end

  # --only "glob1,glob2" restricts validation to matching task names (smoke runs,
  # single-family checks). No filter → the whole corpus.
  defp match_only?(_name, nil), do: true

  defp match_only?(name, patterns) do
    patterns
    |> String.split(",", trim: true)
    |> Enum.any?(fn glob ->
      Regex.match?(~r/\A#{glob |> Regex.escape() |> String.replace("\\*", ".*")}\z/, name)
    end)
  end

  # Tasks with a missing solution.ex (or a dir Discovery could not classify) used to
  # vanish from validation — corpus rot was invisible. Both are now failures.
  # Unclassified dirs are computed against the FULL discovery, then scoped by --only
  # like everything else.
  defp split_corpus(discovered, only) do
    {found, missing} =
      discovered
      |> Enum.filter(&match_only?(&1.name, only))
      |> Enum.split_with(& &1.found)

    classified = MapSet.new(discovered, & &1.name)

    unclassified =
      for dir <- Path.wildcard("tasks/*"),
          File.dir?(dir),
          name = Path.basename(dir),
          not MapSet.member?(classified, name),
          match_only?(name, only),
          do: name

    failures =
      Enum.map(missing, &{:fail, &1.name, "solution.ex missing — task cannot be validated"}) ++
        Enum.map(
          unclassified,
          &{:fail, &1, "unclassifiable dir (no harness, not FIM-shaped) — dead weight or rot"}
        )

    {found, failures}
  end

  defp finish(true, msg) do
    IO.puts("\n" <> msg)
    shutdown(0)
  end

  defp finish(false, _msg), do: shutdown(1)

  # `System.halt/1` terminates without flushing buffered stdout — under output
  # redirection (CI, `> log`) that drops the whole report. `System.stop/1` shuts
  # down gracefully (flushing stdio) and exits with the given code; we then block.
  defp shutdown(code) do
    System.stop(code)
    Process.sleep(:infinity)
  end

  defp persist_failures([]) do
    File.mkdir_p!("results")
    File.write!("results/perfect_failures.txt", "")
    :ok
  end

  defp persist_failures(failures) do
    File.mkdir_p!("results")
    path = "results/perfect_failures.txt"
    body = Enum.map_join(failures, "\n", fn {:fail, name, why} -> "#{name}\t#{why}" end)
    File.write!(path, body <> "\n")
    IO.puts("  (#{length(failures)} failures written to #{path})")
  end

  # ── perfect-score (default) ─────────────────────────────────────────────────

  # First pass grades every task in parallel. Suspects (imperfect) split by cause:
  # only a TEST failure can flake under parallel load, so only those are re-checked
  # (serially, unloaded); deterministic deductions (warnings, docs, line length)
  # never flake and are reported straight away. A recovered flake still PASSES the
  # gate but is appended to logs/flaky.jsonl — repeat offenders there are harnesses
  # that need a fake clock, not forgiveness.
  defp perfect_score(tasks, stability) do
    IO.puts("Perfect-score: #{length(tasks)} tasks (overall must be 1.0) ...")

    {_perfect, suspects} =
      tasks
      |> pmap(fn task ->
        json = eval(task.dir, task.solution)
        ok? = perfect?(json)
        IO.write(if ok?, do: ".", else: "s")
        {task, json, ok?}
      end)
      |> Enum.split_with(fn {_t, _j, ok?} -> ok? end)

    {flaky_prone, deterministic} =
      Enum.split_with(suspects, fn {_t, json, _} -> test_failure?(json) end)

    if flaky_prone != [] do
      IO.puts(
        "\nRe-checking #{length(flaky_prone)} test-failure suspects " <>
          "(flake filter, stability=#{stability}) ..."
      )
    end

    recovered =
      for {task, first_json, _} <- flaky_prone, reduce: [] do
        acc ->
          if Enum.all?(1..stability, fn _ -> perfect?(eval(task.dir, task.solution)) end) do
            IO.write("r")
            log_flake(task, first_json)
            acc
          else
            IO.write("F")
            [failrec(task, first_json) | acc]
          end
      end

    Enum.reverse(recovered) ++ Enum.map(deterministic, fn {t, j, _} -> failrec(t, j) end)
  end

  # A task that fails under parallel load and recovers serially is timing-sensitive.
  # The ledger is the quarantine signal `dataset_stats`/reviews can aggregate.
  defp log_flake(task, first_json) do
    File.mkdir_p!("logs")

    entry = %{
      task: task.name,
      ts: DateTime.utc_now() |> DateTime.to_iso8601(),
      detail: Enum.join(get_in(first_json, ["score", "reasons"]) || [describe(first_json)], "; ")
    }

    File.write!("logs/flaky.jsonl", Jason.encode!(entry) <> "\n", [:append])
  end

  defp failrec(task, json) do
    reasons = get_in(json, ["score", "reasons"]) || [describe(json)]
    overall = get_in(json, ["score", "overall"])
    {:fail, task.name, "overall=#{inspect(overall)} — #{Enum.join(reasons, "; ")}"}
  end

  # Perfect means the RAW invariants hold, not the rounded overall: `overall` is
  # rounded to 2 places, so a 139/140 harness (raw 0.995) rounds to 1.0 and would
  # sneak a failing test through a `>= 1.0` check.
  defp perfect?(json) do
    overall = get_in(json, ["score", "overall"])

    is_number(overall) and overall >= 1.0 and
      json["compiled"] == true and
      (json["compile_warnings"] || 0) == 0 and
      (json["tests_passed"] || 0) > 0 and
      (json["tests_failed"] || 0) == 0 and
      (json["tests_errors"] || 0) == 0
  end

  defp test_failure?(json) do
    (json["tests_failed"] || 0) > 0 or (json["tests_errors"] || 0) > 0
  end

  # ── opt-in lighter checks ───────────────────────────────────────────────────

  defp reference_green(tasks) do
    IO.puts("Reference-green: #{length(tasks)} tasks ...")

    tasks
    |> pmap(fn task ->
      json = eval(task.dir, task.solution)

      cond do
        Map.has_key?(json, "skipped") ->
          IO.write("s")
          nil

        json["compiled"] == true and json["tests_failed"] == 0 and
            (json["tests_errors"] || 0) == 0 and (json["tests_passed"] || 0) > 0 ->
          IO.write(".")
          nil

        true ->
          IO.write("F")
          {:fail, task.name, describe(json)}
      end
    end)
    |> collect()
  end

  defp fim_mutation(tasks) do
    fims = Enum.filter(tasks, &(&1.shape == :fim))
    IO.puts("FIM mutation: #{length(fims)} tasks ...")

    fims
    |> pmap(fn task ->
      mutant = mutant_file(task.solution, &EvalTask.Fim.mutate/1)
      verdict = mutant_verdict(task, mutant, "target under-tested")
      File.rm(mutant)
      verdict
    end)
    |> collect()
  end

  # Whole-solution mutation for every shape whose harness runs directly against the
  # solution: :single, :multifile (bundle-aware gutting), and :write_test (the gold
  # harness must fail when the module under test is gutted). :fim has its own mode
  # (--fim); :test_fim non-vacuousness is gated per-block at mint time (isolation
  # gate) and a gutted single test block is not meaningfully mutable here.
  defp whole_mutation(tasks) do
    {mutable, rest} = Enum.split_with(tasks, &(&1.shape in [:single, :multifile, :write_test]))
    skipped = Enum.frequencies_by(rest, & &1.shape)

    IO.puts(
      "Whole-solution mutation: #{length(mutable)} tasks " <>
        "(skipping #{inspect(skipped)} — fim has --fim; tfim is gated at mint time) ..."
    )

    mutable
    |> pmap(fn task ->
      source = File.read!(task.solution)
      mutated = GenTask.Mutation.mutate(source)

      if mutated == source do
        IO.write("X")
        {:fail, task.name, "mutant could not be constructed (source unchanged) — unverifiable"}
      else
        mutant = mutant_file(task.solution, fn _ -> mutated end)
        verdict = mutant_verdict(task, mutant, "harness is vacuous")
        File.rm(mutant)
        verdict
      end
    end)
    |> collect()
  end

  # A kill needs positive evidence that the harness observed the mutation: the mutant
  # COMPILED and the harness then FAILED or ERRORED. Harness errors count — a macro
  # module's gutted `defmacro` raises at harness COMPILE time (expansion executes the
  # body), which grades as `tests_errors: 1, tests_total: 0`; since the same harness is
  # green against the reference, an error appearing only against the mutant is caused
  # by the mutation. A non-compiling MUTANT proves nothing (the harness never saw it),
  # and a green mutant run means the harness asserts nothing the mutation broke.
  defp mutant_verdict(task, mutant_path, survived_msg) do
    json = eval(task.dir, mutant_path)
    failed = (json["tests_failed"] || 0) > 0 or (json["tests_errors"] || 0) > 0

    cond do
      json["compiled"] == true and failed ->
        IO.write(".")
        nil

      json["compiled"] != true ->
        IO.write("C")
        {:fail, task.name, "mutant did not COMPILE — coverage unverifiable"}

      (json["tests_passed"] || 0) > 0 ->
        IO.write("U")
        {:fail, task.name, "mutant PASSED — #{survived_msg}"}

      true ->
        IO.write("?")
        {:fail, task.name, "mutant run was inconclusive (no tests ran, no errors) — unverifiable"}
    end
  end

  # ── semantic mutants (docs/10 R10, REPORT-ONLY) ─────────────────────────────

  # Measures assertion TIGHTNESS: each first-order semantic mutant (comparison
  # swap, off-by-one, :ok↔:error, boolean flip) is a behavior change; a survivor
  # is a change no test noticed. No gate — the corpus was never held to this bar;
  # measure first (docs/10 R10), then decide thresholds. EXPENSIVE: up to
  # `--sm-limit` (default 40) evals per task — scope with --only for spot checks.
  defp semantic_report(tasks, limit) do
    mutable = Enum.filter(tasks, &(&1.shape in [:single, :multifile, :write_test]))

    IO.puts(
      "Semantic mutants (report-only): #{length(mutable)} tasks, ≤#{limit} mutants each ..."
    )

    rows =
      mutable
      |> pmap(fn task ->
        source = File.read!(task.solution)
        mutants = GenTask.Mutation.semantic_mutants(source, limit)

        {killed, survivors, dropped} =
          Enum.reduce(mutants, {0, [], 0}, fn {label, mutated}, {k, s, d} ->
            path =
              Path.join(System.tmp_dir!(), "smut_#{System.unique_integer([:positive])}.ex")

            File.write!(path, mutated)
            json = eval(task.dir, path)
            File.rm(path)

            failed = (json["tests_failed"] || 0) > 0 or (json["tests_errors"] || 0) > 0

            cond do
              json["compiled"] != true -> {k, s, d + 1}
              failed -> {k + 1, s, d}
              true -> {k, [label | s], d}
            end
          end)

        row = %{
          task: task.name,
          killed: killed,
          total: killed + length(survivors),
          survivors: Enum.reverse(survivors),
          dropped: dropped,
          ts: DateTime.utc_now() |> DateTime.to_iso8601()
        }

        File.mkdir_p!("logs")
        File.write!("logs/semantic_mutants.jsonl", Jason.encode!(row) <> "\n", [:append])
        IO.write(".")
        row
      end)

    IO.puts("\n\n=== SEMANTIC-MUTANT REPORT (kill-rate = behavior changes noticed) ===")

    scored = Enum.filter(rows, &(&1.total > 0))
    rates = Enum.map(scored, &(&1.killed / &1.total))

    if rates != [] do
      mean = Float.round(Enum.sum(rates) / length(rates), 3)
      total_m = Enum.sum(Enum.map(scored, & &1.total))
      total_k = Enum.sum(Enum.map(scored, & &1.killed))
      dropped = Enum.sum(Enum.map(rows, & &1.dropped))

      IO.puts(
        "  tasks: #{length(scored)}   mutants: #{total_m}   killed: #{total_k} " <>
          "(#{Float.round(100.0 * total_k / max(total_m, 1), 1)}%)   " <>
          "mean per-task rate: #{mean}   non-compiling dropped: #{dropped}"
      )

      IO.puts("\n  kill-rate histogram:")

      for lo <- 0..9 do
        n = Enum.count(rates, &(&1 >= lo / 10 and (&1 < (lo + 1) / 10 or (lo == 9 and &1 <= 1.0))))
        IO.puts("    #{lo / 10}–#{(lo + 1) / 10}: #{String.duplicate("█", n)} #{n}")
      end

      IO.puts("\n  20 weakest tasks (most unnoticed behavior changes):")

      scored
      |> Enum.sort_by(&{&1.killed / &1.total, -&1.total})
      |> Enum.take(20)
      |> Enum.each(fn r ->
        IO.puts(
          "    - #{r.task}: #{r.killed}/#{r.total} " <>
            "(survivors: #{Enum.join(Enum.take(r.survivors, 4), "; ")}#{if length(r.survivors) > 4, do: "; …"})"
        )
      end)
    else
      IO.puts("  no mutable tasks matched")
    end
  end

  defp mutant_file(solution_path, mutate_fun) do
    mutated = solution_path |> File.read!() |> mutate_fun.()
    path = Path.join(System.tmp_dir!(), "mutant_#{System.unique_integer([:positive])}.ex")
    File.write!(path, mutated)
    path
  end

  # ── shared ──────────────────────────────────────────────────────────────────

  # Each eval runs under a wall-clock KILL so one pathological solution (compile-time
  # infinite loop, hung test) cannot stall the whole sweep. Exit 137 = killed.
  defp eval(dir, solution) do
    args = ["--signal=KILL", eval_timeout_s(), "elixir", "scripts/eval_task.exs", dir, solution]

    case System.cmd("timeout", args, stderr_to_stdout: false) do
      {out, 0} ->
        out
        |> String.split("\n", trim: true)
        |> Enum.reverse()
        |> Enum.find("{}", &String.starts_with?(&1, "{"))
        |> decode_json()

      {_, code} ->
        %{
          "compiled" => false,
          "tests_failed" => 0,
          "tests_total" => 0,
          "eval_exit" => code,
          "compile_errors" => [
            %{
              "type" => "eval",
              "message" =>
                if(code == 137,
                  do: "eval KILLED after #{eval_timeout_s()}s (EVAL_TIMEOUT_S) — likely a hang",
                  else: "eval crashed with exit #{code}"
                )
            }
          ]
        }
    end
  end

  # A stray non-JSON `{`-line (leaked test output) must fail that one task, not
  # crash the whole sweep.
  defp decode_json(line) do
    case Jason.decode(line) do
      {:ok, json} ->
        json

      {:error, _} ->
        %{
          "compiled" => false,
          "tests_failed" => 0,
          "tests_total" => 0,
          "compile_errors" => [
            %{"type" => "eval", "message" => "unparsable evaluator output: #{inspect(line)}"}
          ]
        }
    end
  end

  defp eval_timeout_s, do: System.get_env("EVAL_TIMEOUT_S", "240")

  defp describe(json) do
    cond do
      json["compiled"] != true ->
        "compile fail: #{inspect(get_in(json, ["compile_errors", Access.at(0), "message"]))}"

      true ->
        "#{json["tests_failed"]}/#{json["tests_total"]} failed"
    end
  end

  # Saturating worker pool (no chunk barrier) — keeps all cores busy. Each item is a
  # fresh eval_task.exs OS process, so concurrency ~= cores gives near-linear speedup.
  # The per-item wall-clock KILL in `eval/2` bounds each task, so a generous stream
  # timeout here is a backstop, not the limiter.
  defp pmap(items, fun) do
    items
    |> Task.async_stream(fun,
      max_concurrency: concurrency(),
      timeout: :infinity,
      ordered: false
    )
    |> Enum.map(fn {:ok, r} -> r end)
  end

  defp concurrency do
    case System.get_env("EVAL_CONCURRENCY") do
      nil -> min(16, max(4, System.schedulers_online() - 2))
      v -> String.to_integer(v)
    end
  end

  defp collect(results), do: Enum.filter(results, &match?({:fail, _, _}, &1))

  defp report(label, []), do: IO.puts("  #{label}: all pass ✓")

  defp report(label, failures) do
    IO.puts("  #{label}: #{length(failures)} FAILED:")
    for {:fail, name, why} <- failures, do: IO.puts("    - #{name}: #{why}")
  end
end

Validate.main(System.argv())
