# close_gaps.exs — T2.2-T: close semantic-review harness gaps with ADD-ONLY tests.
#
# Input: the confirmed findings in logs/semantic_review.jsonl (review +
# adversarial verify, docs/15 T2.2). This tool takes every family with at least
# one confirmed `harness_gap` finding and makes ONE strengthen-mold attempt to
# close ALL of that family's confirmed findings with ADDED tests — the
# documented-behavior coverage the review proved missing (untested defaults,
# unexercised promised modes, non-discriminating tests shadowed by sharper
# additions).
#
# Same hard gates as strengthen_harnesses.exs (they arbitrate rule 10 for us —
# a wrong finding produces a rejected family, never corpus damage):
#   add-only (existing blocks byte-verbatim: tfim children carve them);
#   reference green + zero warnings + house lints; whole-module raise-mutant
#   killed; semantic re-measure must not DROP; BLIND gate (a prompt-only solve
#   must pass the stronger harness — the arbiter of "was that promise really
#   documented"); apply + wt_ twin + tfim embed resync, restore on failure.
#
# gold_defect / prompt_defect findings are NEVER acted on here (hand work, per
# family, like 095_003/031_002) — they are shown to the model as context only
# when the family also has gaps, so added tests do not fight a known gold bug.
#
# Usage:
#   mix run scripts/close_gaps.exs                      # DRY: the work list
#   mix run scripts/close_gaps.exs -- --go --only "021_002*"   # pilot
#   mix run scripts/close_gaps.exs -- --go              # all gap families
#   mix run scripts/close_gaps.exs -- --go --high-only  # only families with a HIGH gap
#   mix run scripts/close_gaps.exs -- --report          # ledger summary
#
# ⚠️ Run --go SCOPED (--only). Six families were closed BY HAND on 07-14
# (110_004, 100_004, 110_001, 020_004, 104_002, 032_001 — docs/15), so no
# tool row matches their current harness sha and the dry list shows them as
# phantom "todo" forever. An unscoped --go re-attempts them with paid calls.
#
# Ledger: logs/close_gaps.jsonl (gate-sha-stamped rows keyed by
# harness_sha_before; resume skips families whose CURRENT harness has a
# success row). Candidates archived to logs/gap_candidates/ before gating.

alias GenTask.{Config, Cycle, CycleLog, Evaluator, Mutation, Reply, Variations}

defmodule CloseGaps do
  @moduledoc false

  @review_ledger "logs/semantic_review.jsonl"
  @ledger "logs/close_gaps.jsonl"

  # Env-overridable so tests can sandbox the ledgers and the corpus dir.
  defp review_ledger, do: System.get_env("CLOSE_GAPS_REVIEW_LEDGER") || @review_ledger
  defp ledger, do: System.get_env("CLOSE_GAPS_LEDGER") || @ledger
  defp tasks_root, do: System.get_env("CLOSE_GAPS_TASKS_DIR") || "tasks"
  @sm_limit 40

  def main(argv) do
    argv = Enum.drop_while(argv, &(&1 == "--"))

    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [go: :boolean, report: :boolean, only: :string, high_only: :boolean]
      )

    cond do
      opts[:report] -> report()
      opts[:go] -> go(opts)
      true -> dry(opts)
    end
  end

  # ── population: families with confirmed harness_gap findings ───────────────

  defp gap_families(opts) do
    review_ledger()
    |> File.stream!()
    |> Enum.flat_map(fn line ->
      case Jason.decode(line) do
        {:ok, %{"task" => task, "confirmed" => confirmed}}
        when is_list(confirmed) and confirmed != [] ->
          if String.contains?(task, ":"), do: [], else: [{task, confirmed}]

        _ ->
          []
      end
    end)
    # Latest row per task wins (re-reviews append).
    |> Map.new()
    |> Enum.filter(fn {task, confirmed} ->
      File.dir?(Path.join(tasks_root(), task)) and
        Enum.any?(confirmed, &(&1["class"] == "harness_gap")) and
        (opts[:high_only] != true or
           Enum.any?(confirmed, &(&1["class"] == "harness_gap" and &1["severity"] == "high")))
    end)
    |> Enum.sort()
  end

  # A family is done only when an applied row covers BOTH the current harness
  # and the current findings: a new review/seed row for an already-closed
  # harness re-opens it (found live 2026-07-15 — three hand-seeded gaps read
  # DONE because the resume key was the harness sha alone). Old rows carry no
  # gaps_sha; they count only for findings that existed when they were written.
  @doc false
  def done?(task, confirmed) do
    dir = Path.join(tasks_root(), task)
    current = harness_sha(dir)
    digest = gaps_sha(confirmed)

    Enum.any?(success_rows(), fn row ->
      row["harness_sha_after"] == current and
        (row["gaps_sha"] == digest or
           (row["gaps_sha"] == nil and row["ts"] >= latest_review_ts(task)))
    end)
  end

  @doc false
  def gaps_sha(confirmed) do
    confirmed
    |> Enum.filter(&(&1["class"] == "harness_gap"))
    |> Enum.map(&(&1["evidence"] <> "|" <> &1["why"]))
    |> Enum.sort()
    |> Enum.join("\n")
    |> CycleLog.content_sha()
  end

  defp latest_review_ts(task) do
    review_ledger()
    |> File.stream!()
    |> Enum.reduce("", fn line, acc ->
      case Jason.decode(line) do
        {:ok, %{"task" => ^task, "ts" => ts}} -> ts
        _ -> acc
      end
    end)
  end

  defp dry(opts) do
    IO.puts("Gap-closing work list (confirmed harness_gap findings per family):\n")

    families = gap_families(opts)

    for {task, confirmed} <- families do
      gaps = Enum.count(confirmed, &(&1["class"] == "harness_gap"))
      other = length(confirmed) - gaps
      high = Enum.any?(confirmed, &(&1["severity"] == "high"))
      status = if done?(task, confirmed), do: "DONE", else: "todo"

      IO.puts(
        "  #{task}: #{gaps} gap(s)#{if other > 0, do: " (+#{other} gold/prompt finding(s), hand scope)", else: ""}" <>
          "#{if high, do: " [HIGH]", else: ""} — #{status}"
      )
    end

    IO.puts("\n#{length(families)} family(ies); ~2 LLM calls each. Run with `-- --go`.")
  end

  # ── the loop ────────────────────────────────────────────────────────────────

  defp go(opts) do
    refuse_if_generate_alive!()
    cfg = Config.new([])

    todo =
      gap_families(opts)
      |> Enum.filter(fn {task, _} -> match_only?(task, opts[:only]) end)
      |> Enum.reject(fn {task, confirmed} -> done?(task, confirmed) end)

    IO.puts("closing gaps in #{length(todo)} family(ies), sequential, ledger #{ledger()}\n")

    Enum.each(Enum.with_index(todo, 1), fn {{task, confirmed}, i} ->
      IO.write("[#{i}/#{length(todo)}] #{task} ... ")
      row = close(cfg, Path.join(tasks_root(), task), confirmed)
      append_ledger(row)
      IO.puts("#{row.verdict}#{if row[:detail], do: " — " <> row.detail, else: ""}")
    end)

    report()
  end

  defp close(cfg, dir, confirmed) do
    id = Path.basename(dir)
    prompt = File.read!(Path.join(dir, "prompt.md"))
    solution = File.read!(Path.join(dir, "solution.ex"))
    harness0 = File.read!(Path.join(dir, "test_harness.exs"))
    manifest = read_optional(Path.join(dir, "manifest.exs"))

    base = %{
      family: id,
      harness_sha_before: CycleLog.content_sha(harness0),
      gaps_sha: gaps_sha(confirmed),
      gate_sha: gate_sha(),
      ts: now()
    }

    {rate0, _surv, _k, _t} = measure(cfg, id, prompt, solution, harness0, manifest)

    with {:ok, harness1} <- gen_gap_tests(cfg, id, prompt, solution, harness0, confirmed),
         :ok <- add_only(harness0, harness1),
         {:ok, json} <- grade_green(cfg, id, prompt, solution, harness1, manifest),
         :ok <- lints(json, prompt, solution, harness1),
         :ok <- whole_mutant_killed(cfg, id, prompt, solution, harness1, manifest),
         {rate1, surv1, k1, t1} = measure(cfg, id, prompt, solution, harness1, manifest),
         :ok <- no_drop(rate0, rate1),
         :ok <- blind_gate(cfg, id, prompt, harness0, harness1, manifest) do
      apply_result = apply!(dir, harness0, harness1)

      if apply_result in [:applied, :applied_wt_divergent],
        do: record_measurement(dir, id, k1, t1, surv1)

      Map.merge(base, %{
        verdict: apply_result,
        rate_before: rate0,
        rate_after: rate1,
        tests_added: length(test_blocks(harness1)) - length(test_blocks(harness0)),
        gaps_seeded: Enum.count(confirmed, &(&1["class"] == "harness_gap")),
        harness_sha_after: CycleLog.content_sha(harness1)
      })
    else
      {:error, why} ->
        Map.merge(base, %{verdict: :rejected, rate_before: rate0, detail: why})
    end
  end

  # ── the call ────────────────────────────────────────────────────────────────

  defp gen_gap_tests(cfg, id, prompt, solution, harness, confirmed) do
    gaps = Enum.filter(confirmed, &(&1["class"] == "harness_gap"))
    others = confirmed -- gaps

    system =
      "You are a senior Elixir engineer closing verified test-coverage gaps. You reply " <>
        "with ONLY a single <file path=\"test_harness.exs\">…</file> block containing " <>
        "the complete new harness, nothing else."

    user = """
    An adversarially-verified review of this task found DOCUMENTED behavior the
    harness never exercises. ADD tests that close each gap below, under hard
    rules:

    - ADD ONLY: every existing test block must remain byte-for-byte identical
      (they are carved into derived tasks); no renames, no edits, no deletions.
      When a gap says an existing test "does not discriminate", do not touch
      it — add a SHARPER test beside it that does.
    - Every new assertion must be justified by an explicit statement in the
      task prompt below — never assert undocumented behavior, internal state,
      or exact error-message text (assert the exception TYPE only).
    - A hard lint REJECTS the whole harness if any NEW test uses
      `:sys.get_state`/`:sys.replace_state`, `assert inspect(...)`, sends a
      process an internal message the prompt does not document, passes an
      undocumented `:infinity`, or adds `Process.sleep`. Observe behavior only
      through the public API (injected clocks/hooks are documented API). If a
      gap cannot be closed that way — e.g. it requires real wall-clock timer
      behavior and the module has no injected clock — SKIP that gap; a
      partial close is better than a flaky or reach-in test.
    - Comments must describe BEHAVIOR, never the process that produced the
      test: no review citations, no `--- added` banners, no repair markers.
    - Same conventions as the existing harness (`use ExUnit.Case, async: false`,
      no `ExUnit.start()`, self-contained, ZERO compile warnings, lines ≤ 98
      columns, process-unique temp paths via `System.pid()` +
      `System.unique_integer/1` where needed).
    - Prefer few, sharp tests; name each for the behavior it pins.

    === VERIFIED COVERAGE GAPS (close these) ===
    #{Enum.map_join(gaps, "\n\n", &format_finding/1)}
    #{other_findings_section(others)}
    === task prompt.md ===
    #{prompt}

    === reference solution.ex ===
    #{solution}

    === current test_harness.exs ===
    #{harness}
    """

    case Cycle.opus(cfg, id, "close_gaps", system, user) do
      {:ok, text, _meta} ->
        case Reply.parse(text) do
          %{"test_harness.exs" => h} when is_binary(h) and h != "" ->
            candidate = canonicalize(h)
            save_candidate(id, harness, candidate)
            {:ok, candidate}

          _ ->
            {:error, "reply carried no test_harness.exs block"}
        end

      {:error, reason} ->
        {:error, "close_gaps call failed: #{inspect(reason)}"}
    end
  end

  defp format_finding(f) do
    "- [#{f["severity"]}] #{f["why"]}\n  Evidence: #{f["evidence"]}"
  end

  # Known gold/prompt findings are context only: the model must not write a
  # test that PINS behavior a pending hand-fix will change.
  defp other_findings_section([]), do: ""

  defp other_findings_section(others) do
    """

    === KNOWN OPEN GOLD/PROMPT FINDINGS (context only — do NOT write tests that
    pin the affected behavior; those are pending hand fixes) ===
    #{Enum.map_join(others, "\n\n", &format_finding/1)}
    """
  end

  defp save_candidate(id, harness_before, candidate) do
    dir = "logs/gap_candidates"
    File.mkdir_p!(dir)
    sha8 = String.slice(CycleLog.content_sha(harness_before), 0, 8)
    File.write!(Path.join(dir, "#{id}__#{sha8}.exs"), candidate)
  end

  defp canonicalize(src) do
    src
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> String.trim_trailing("\n")
    |> Kernel.<>("\n")
  rescue
    _ -> src
  end

  # ── gates (the strengthen suite, verbatim shapes) ───────────────────────────

  defp add_only(harness0, harness1) do
    missing =
      harness0
      |> test_blocks()
      |> Enum.reject(fn block -> String.contains?(harness1, block) end)

    if missing == [],
      do: :ok,
      else: {:error, "modified/dropped #{length(missing)} existing test block(s) (add-only rule)"}
  end

  defp test_blocks(harness) do
    lines = String.split(harness, "\n")

    for cand <- GenTask.TestFim.carvable_blocks(harness),
        do: lines |> Enum.slice(cand.s..cand.e) |> Enum.join("\n")
  end

  defp grade_green(cfg, id, prompt, solution, harness, manifest) do
    json = grade(cfg, id, prompt, solution, harness, manifest)

    cond do
      not Evaluator.green?({:ok, json}) ->
        {:error, "reference not green vs new harness: " <> Cycle.reason_for({:ok, json})}

      (json["compile_warnings"] || 0) > 0 ->
        {:error, "new harness compiles with warnings: #{inspect(json["warning_details"])}"}

      true ->
        {:ok, json}
    end
  end

  # The min-test-count floor is today's accept standard; grandfathered
  # harnesses may sit below it even after the gap tests land. That one
  # shortfall must not block closing VERIFIED gaps (same exemption as
  # rewrite_reachins.exs — the count debt is strengthen/T1.4 scope). Every
  # other shortfall stays a hard reject.
  @count_shortfall ~r/^only \d+ test\(s\) — the harness needs at least/

  defp lints(json, prompt, solution, harness) do
    files = %{"prompt.md" => prompt, "solution.ex" => solution, "test_harness.exs" => harness}

    case Evaluator.quality_shortfall(json, files) do
      nil ->
        :ok

      shortfall ->
        real =
          shortfall
          |> String.split("; ")
          |> Enum.reject(&Regex.match?(@count_shortfall, &1))

        if real == [],
          do: :ok,
          else: {:error, "house/harness lint: " <> Enum.join(real, "; ")}
    end
  end

  defp whole_mutant_killed(cfg, id, prompt, solution, harness, manifest) do
    mutant = Mutation.mutate(solution)
    json = grade_override(cfg, id, prompt, solution, harness, manifest, mutant)
    grade = {:ok, json}

    if Evaluator.killed_by_tests?(grade) or Evaluator.errored_against_mutant?(grade),
      do: :ok,
      else: {:error, "whole-module raise-mutant SURVIVES the new harness"}
  end

  defp no_drop(rate0, rate1) do
    if rate1 >= rate0,
      do: :ok,
      else:
        {:error,
         "semantic kill rate DROPPED (#{Float.round(rate0, 2)} → #{Float.round(rate1, 2)})"}
  end

  defp blind_gate(cfg, id, prompt, harness0, harness1, manifest) do
    case Variations.blind_solution("gaps_blind_#{id}", prompt, cfg) do
      {:ok, blind} ->
        json = grade(cfg, id, prompt, blind, harness1, manifest)

        if Evaluator.green?({:ok, json}) do
          :ok
        else
          original = MapSet.new(test_names(harness0))

          failing =
            (json["test_failures"] || [])
            |> Enum.map(&normalize_test_name(&1["test"]))
            |> Enum.reject(&(&1 == ""))

          {pre_existing, added} = Enum.split_with(failing, &MapSet.member?(original, &1))

          cond do
            json["compiled"] != true ->
              {:error, "blind solve did not COMPILE (solver defect) — retry the family"}

            added == [] and pre_existing != [] ->
              {:error,
               "INCONCLUSIVE: blind solver failed only PRE-EXISTING tests " <>
                 "(#{Enum.join(Enum.take(pre_existing, 3), "; ")}) — solver-weak this " <>
                 "attempt; retry the family"}

            true ->
              {:error,
               "blind solver fails ADDED test(s) — either the added test pins more than " <>
                 "the prompt states (the gap finding may be wrong) or the solver slipped " <>
                 "on documented behavior (rule 10 — hand-check before retrying). " <>
                 "Failing: " <> Enum.join(Enum.take(added, 4), "; ")}
          end
        end

      {:error, reason} ->
        {:error, "blind solve call failed: #{inspect(reason)}"}
    end
  end

  defp test_names(harness) do
    ~r/^\s*(?:test|property)\s+"((?:[^"\\]|\\.)*)"/m
    |> Regex.scan(harness, capture: :all_but_first)
    |> Enum.map(fn [n] -> n end)
  end

  defp normalize_test_name(nil), do: ""

  defp normalize_test_name(t) do
    t |> to_string() |> String.replace_prefix("test ", "") |> String.trim()
  end

  # ── apply + propagate (strengthen's, verbatim) ──────────────────────────────

  defp apply!(dir, harness0, harness1) do
    id = Path.basename(dir)
    harness_path = Path.join(dir, "test_harness.exs")
    File.write!(harness_path, harness1)

    wt = wt_twin(id)

    wt_status =
      cond do
        wt == nil ->
          :no_wt

        File.read!(Path.join(wt, "test_harness.exs")) == harness0 ->
          File.write!(Path.join(wt, "test_harness.exs"), harness1)
          :updated

        true ->
          :divergent_hand_triage
      end

    fam = id |> String.split("_") |> Enum.take(2) |> Enum.join("_")

    {out, status} =
      System.cmd(
        "mix",
        ["run", "scripts/resync_tfim_embeds.exs", "--", "--only", "*#{fam}*", "--apply"],
        stderr_to_stdout: true
      )

    if status == 0 and not String.contains?(out, "error") do
      if wt_status == :divergent_hand_triage, do: :applied_wt_divergent, else: :applied
    else
      File.write!(harness_path, harness0)
      if wt_status == :updated, do: File.write!(Path.join(wt, "test_harness.exs"), harness0)
      :reverted_tfim_resync_failed
    end
  end

  defp wt_twin(id) do
    base = String.replace_suffix(id, "_01", "")

    case Path.wildcard("tasks/wt_#{base}") do
      [dir] -> dir
      _ -> nil
    end
  end

  # ── measurement + grading plumbing (strengthen's, verbatim) ─────────────────

  defp measure(cfg, id, prompt, solution, harness, manifest) do
    mutants = Mutation.semantic_mutants(solution, @sm_limit)

    {killed, survivors} =
      Enum.reduce(mutants, {0, []}, fn {label, mutated}, {k, s} ->
        json = grade_override(cfg, id, prompt, solution, harness, manifest, mutated)
        failed = (json["tests_failed"] || 0) > 0 or (json["tests_errors"] || 0) > 0

        cond do
          json["compiled"] != true -> {k, s}
          failed -> {k + 1, s}
          true -> {k, [label | s]}
        end
      end)

    total = killed + length(survivors)
    {if(total > 0, do: killed / total, else: 1.0), Enum.reverse(survivors), killed, total}
  end

  defp record_measurement(dir, id, killed, total, survivors) do
    row = %{
      task: id,
      killed: killed,
      total: total,
      survivors: survivors,
      dropped: 0,
      solution_sha: file_sha(dir, "solution.ex"),
      harness_sha: file_sha(dir, "test_harness.exs"),
      gate_sha: CycleLog.gate_sha([Mutation, Evaluator]),
      ts: now()
    }

    File.write!("logs/semantic_mutants.jsonl", Jason.encode!(row) <> "\n", [:append])
  end

  defp grade(cfg, id, prompt, solution, harness, manifest) do
    dir = stage(cfg, id, prompt, solution, harness, manifest)

    case Evaluator.grade(dir, cfg) do
      {:ok, json} -> json
      :timeout_or_crash -> %{"compiled" => false, "tests_failed" => 0, "tests_errors" => 0}
    end
  end

  defp grade_override(cfg, id, prompt, solution, harness, manifest, override_src) do
    dir = stage(cfg, id, prompt, solution, harness, manifest)

    path =
      Path.join(
        System.tmp_dir!(),
        "gaps_#{System.pid()}_#{System.unique_integer([:positive])}.ex"
      )

    File.write!(path, override_src)

    result =
      case Evaluator.grade(dir, cfg, path) do
        {:ok, json} -> json
        :timeout_or_crash -> %{"compiled" => false, "tests_failed" => 0, "tests_errors" => 0}
      end

    File.rm(path)
    result
  end

  defp stage(cfg, id, prompt, solution, harness, manifest) do
    files =
      %{"prompt.md" => prompt, "solution.ex" => solution, "test_harness.exs" => harness}
      |> then(&if manifest, do: Map.put(&1, "manifest.exs", manifest), else: &1)

    Evaluator.stage!(Path.join(cfg.staging_dir, "gaps_#{id}"), files)
  end

  # ── ledger / report / misc ──────────────────────────────────────────────────

  defp gate_sha, do: CycleLog.gate_sha([Mutation, Evaluator, GenTask.TestFim])

  defp append_ledger(row) do
    File.mkdir_p!("logs")
    File.write!(ledger(), Jason.encode!(row) <> "\n", [:append])
  end

  defp success_rows do
    case File.read(ledger()) do
      {:ok, body} ->
        body
        |> String.split("\n", trim: true)
        |> Enum.flat_map(fn line ->
          case Jason.decode(line) do
            {:ok, %{"verdict" => v, "harness_sha_after" => sha} = row}
            when v in ["applied", "applied_wt_divergent"] and is_binary(sha) ->
              [row]

            _ ->
              []
          end
        end)

      _ ->
        []
    end
  end

  defp report do
    case File.read(ledger()) do
      {:ok, body} ->
        rows = body |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)
        freq = Enum.frequencies_by(rows, & &1["verdict"])
        IO.puts("\n=== CLOSE-GAPS LEDGER (#{length(rows)} row(s)) === #{inspect(freq)}")

        for r <- rows, r["verdict"] in ["applied", "applied_wt_divergent"] do
          IO.puts(
            "  #{r["family"]}: #{fmt(r["rate_before"])} → #{fmt(r["rate_after"])} " <>
              "(+#{r["tests_added"]} test(s) for #{r["gaps_seeded"]} gap(s))"
          )
        end

      _ ->
        IO.puts("no ledger yet")
    end
  end

  defp fmt(nil), do: "?"
  defp fmt(r), do: Float.round(r * 1.0, 2)

  defp match_only?(_f, nil), do: true

  defp match_only?(f, globs) do
    globs
    |> String.split(",", trim: true)
    |> Enum.any?(fn g ->
      re = g |> String.trim() |> Regex.escape() |> String.replace("\\*", ".*")
      Regex.match?(~r/#{re}/, f)
    end)
  end

  defp harness_sha(dir), do: CycleLog.content_sha(File.read!(Path.join(dir, "test_harness.exs")))

  defp file_sha(dir, name) do
    path = Path.join(dir, name)
    if File.regular?(path), do: CycleLog.content_sha(File.read!(path))
  end

  defp read_optional(path), do: if(File.regular?(path), do: File.read!(path))

  defp now, do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp refuse_if_generate_alive! do
    {out, _} = System.cmd("pgrep", ["-af", "beam.smp"], stderr_to_stdout: true)

    if String.contains?(out, "generate.exs") do
      IO.puts("REFUSING --go: a generation loop (generate.exs) is alive.")
      System.halt(1)
    end
  end
end

# test/scripts/* load this file with SCRIPTS_NO_AUTORUN=1 to unit-test the
# module's pure decision functions without executing the CLI.
unless System.get_env("SCRIPTS_NO_AUTORUN"), do: CloseGaps.main(System.argv())
