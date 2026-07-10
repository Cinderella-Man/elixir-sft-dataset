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
#   --per-fn-mutants  REPORT-ONLY per-function coverage sweep for every :single task:
#                 mutate EACH public function ALONE to `raise` and grade — a survivor
#                 (harness still passes) means that function is not exercised. Writes a
#                 survivor work-list to results/per_fn_survivors.txt grouped by family.
#                 Unlike --mutants (one whole-module mutant, which any single asserted
#                 function kills) this catches functions the harness never touches; it
#                 also mutation-checks a GenServer's init/1 (exempt only for Plugs).
#   --stability N flake filter must see N consecutive serial passes to recover a
#                 test-failure suspect (default 1). Recovered flakes are always
#                 appended to logs/flaky.jsonl WITH the failing test name + message
#                 from the parallel run — a repeat offender there needs fixing.
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
          per_fn_mutants: :boolean,
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

      opts[:per_fn_mutants] ->
        per_fn_mutation(tasks)
        finish(true, "PER-FN MUTATION SWEEP COMPLETE (report-only — survivor work-list written)")

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
  # `failures` carries the test NAME + assertion message captured at the moment of
  # the parallel failure (the serial re-run would otherwise discard them) — a single
  # occurrence then says WHERE the timing sensitivity is, and two occurrences on the
  # same test are far stronger evidence than two on the same task (docs/10 R9).
  defp log_flake(task, first_json) do
    File.mkdir_p!("logs")

    failures =
      for f <- first_json["test_failures"] || [] do
        %{
          test: f["test"],
          module: f["module"],
          message: String.slice(f["message"] || "", 0, 300)
        }
      end

    entry = %{
      task: task.name,
      ts: DateTime.utc_now() |> DateTime.to_iso8601(),
      detail: Enum.join(get_in(first_json, ["score", "reasons"]) || [describe(first_json)], "; "),
      failures: failures
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

  # ── per-function mutation sweep (REPORT-ONLY work-list) ─────────────────────

  # For every :single task, mutate EACH public function alone to `raise` and grade.
  # A survivor (harness still green with just that function gutted) means the harness
  # does not exercise that function — the whole-module --mutants gate misses this
  # because any ONE asserted function kills the all-at-once mutant. Skips shapes where
  # per-fn mutation is meaningless (bundles — public API spans modules; write_test /
  # fim / tfim — no single-module public API to gut) and :single tasks with no public
  # defs (a bare test/behaviour module). Writes results/per_fn_survivors.txt.
  defp per_fn_mutation(tasks) do
    {single, rest} = Enum.split_with(tasks, &(&1.shape == :single))
    skipped_by_shape = Enum.frequencies_by(rest, & &1.shape)

    {sweepable, no_targets} =
      single
      |> Enum.map(fn task ->
        {task, GenTask.Mutation.per_fn_targets(File.read!(task.solution))}
      end)
      |> Enum.split_with(fn {_task, fns} -> fns != [] end)

    pairs =
      for {task, fns} <- sweepable, {name, arity} <- fns, do: {task, name, arity}

    IO.puts(
      "Per-fn mutation: #{length(sweepable)} single-module tasks, #{length(pairs)} evals " <>
        "(skipping #{inspect(skipped_by_shape)} by shape; " <>
        "#{length(no_targets)} single tasks have no public defs) ..."
    )

    results =
      pairs
      |> pmap(fn {task, name, arity} ->
        mutant =
          mutant_file(task.solution, &GenTask.Mutation.mutate_fn(&1, name, arity))

        verdict = per_fn_verdict(task, name, arity, mutant)
        File.rm(mutant)
        verdict
      end)

    skipped_total = Enum.sum(Map.values(skipped_by_shape)) + length(no_targets)

    per_fn_summarize(
      results,
      length(sweepable),
      skipped_by_shape,
      length(no_targets),
      skipped_total
    )

    persist_per_fn(results, length(sweepable), skipped_total)
  end

  # A per-fn mutant that fails to COMPILE is INCONCLUSIVE, not killed (positive
  # evidence of coverage requires the harness to have observed the mutated code) —
  # and distinctly labelled from an inconclusive "no tests ran" grade. Unlike the
  # whole-solution gate, a single-function compile failure is not the harness's
  # fault, so it must not be reported as a survivor.
  defp per_fn_verdict(task, name, arity, mutant_path) do
    json = eval(task.dir, mutant_path)
    failed = (json["tests_failed"] || 0) > 0 or (json["tests_errors"] || 0) > 0

    {verdict, label} =
      cond do
        json["compiled"] == true and failed -> {:killed, nil}
        json["compiled"] != true -> {:inconclusive, "mutant did not COMPILE"}
        (json["tests_passed"] || 0) > 0 -> {:survived, nil}
        true -> {:inconclusive, "no tests ran, no errors"}
      end

    IO.write(
      case verdict do
        :killed -> "."
        :survived -> "U"
        :inconclusive -> "?"
      end
    )

    %{
      task: task.name,
      family: family(task.name),
      fn: "#{name}/#{arity}",
      verdict: verdict,
      label: label
    }
  end

  # Family = the NNN_VVV prefix (matches dataset_stats.exs grouping); the whole name
  # if it does not match (defensive — every corpus dir does).
  defp family(name) do
    case Regex.run(~r/(\d{3})_(\d{3})/, name) do
      [_, a, b] -> "#{a}_#{b}"
      _ -> name
    end
  end

  defp per_fn_summarize(results, tasks_swept, skipped_by_shape, no_targets, skipped_total) do
    killed = Enum.count(results, &(&1.verdict == :killed))
    survivors = Enum.count(results, &(&1.verdict == :survived))
    inconclusive = Enum.count(results, &(&1.verdict == :inconclusive))

    IO.puts("\n\n=== PER-FN MUTATION SWEEP (survivor = a public fn the harness ignores) ===")

    IO.puts(
      "  tasks swept: #{tasks_swept}   evals: #{length(results)}   " <>
        "killed: #{killed}   SURVIVORS: #{survivors}   inconclusive: #{inconclusive}"
    )

    IO.puts(
      "  skipped-by-shape: #{skipped_total} " <>
        "(#{inspect(skipped_by_shape)} + #{no_targets} single with no public defs)"
    )

    if survivors > 0 do
      IO.puts("\n  SURVIVORS (grouped by family) — remediation work-list:")

      results
      |> Enum.filter(&(&1.verdict == :survived))
      |> Enum.group_by(& &1.family)
      |> Enum.sort_by(fn {fam, _} -> fam end)
      |> Enum.each(fn {fam, rows} ->
        IO.puts("    #{fam}:")
        for r <- Enum.sort_by(rows, & &1.task), do: IO.puts("      - #{r.task}  #{r.fn}")
      end)
    end

    inconc = Enum.filter(results, &(&1.verdict == :inconclusive))

    if inconc != [] do
      IO.puts("\n  INCONCLUSIVE (not survivors — could not verify coverage):")

      for r <- Enum.sort_by(inconc, & &1.task),
          do: IO.puts("      - #{r.task}  #{r.fn} (#{r.label})")
    end
  end

  # The survivor work-list is the deliverable: grouped by family, one {task, fn/arity}
  # per line, with the summary + an inconclusive appendix (compile failures etc. — not
  # survivors, but coverage was not verified, so a remediator will want them too).
  defp persist_per_fn(results, tasks_swept, skipped_total) do
    File.mkdir_p!("results")
    path = "results/per_fn_survivors.txt"

    killed = Enum.count(results, &(&1.verdict == :killed))
    survivors = Enum.filter(results, &(&1.verdict == :survived))
    inconc = Enum.filter(results, &(&1.verdict == :inconclusive))

    header =
      [
        "# Per-function raise-mutation survivors — remediation work-list",
        "# Generated #{DateTime.utc_now() |> DateTime.to_iso8601()}",
        "# Summary: tasks_swept=#{tasks_swept} evals=#{length(results)} " <>
          "killed=#{killed} survivors=#{length(survivors)} " <>
          "inconclusive=#{length(inconc)} skipped_by_shape=#{skipped_total}",
        "# Each SURVIVOR line: <task>\\t<function/arity> — the harness still passes with",
        "# that function's body replaced by `raise`, i.e. it does not exercise it.",
        ""
      ]

    survivor_lines =
      survivors
      |> Enum.group_by(& &1.family)
      |> Enum.sort_by(fn {fam, _} -> fam end)
      |> Enum.flat_map(fn {fam, rows} ->
        ["## family #{fam}"] ++
          (rows |> Enum.sort_by(& &1.task) |> Enum.map(&"#{&1.task}\t#{&1.fn}"))
      end)

    inconc_lines =
      if inconc == [] do
        []
      else
        ["", "# ── INCONCLUSIVE (coverage unverified — NOT survivors) ──"] ++
          (inconc
           |> Enum.sort_by(&{&1.family, &1.task})
           |> Enum.map(&"# #{&1.task}\t#{&1.fn}\t(#{&1.label})"))
      end

    body = Enum.join(header ++ survivor_lines ++ inconc_lines, "\n") <> "\n"
    File.write!(path, body)
    IO.puts("\n  (work-list written to #{path})")
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
        n =
          Enum.count(rates, &(&1 >= lo / 10 and (&1 < (lo + 1) / 10 or (lo == 9 and &1 <= 1.0))))

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
