# strengthen_harnesses.exs — semantic-mutant floor remediation (docs/12 §4.2).
#
# The 2026-07 semantic measurement (logs/semantic_mutants.jsonl) found harnesses
# that notice fewer than half of first-order behavior changes (comparison swaps,
# ±1 on numeric literals, :ok↔:error, bool flips). Weak tests attached to green
# data. This loop STRENGTHENS each such parent harness — one family at a time,
# ledgered, resumable, safe to kill — under HARD gates:
#
#   1. re-measure NOW (the ledger may be stale) — already ≥ floor → skip;
#   2. one LLM call: ADD tests that kill the listed survivors. Adding only —
#      existing test blocks must survive byte-verbatim (tfim children carve
#      them; a modified body would orphan its tfim gold);
#   3. reference still green, zero warnings, house/harness lints clean
#      (incl. the prompt-coverage lint: new asserts must be documented);
#   4. whole-module raise-mutant still killed;
#   5. semantic re-measure with the new harness: rate ≥ floor AND ≥ old rate;
#   6. BLIND gate (the §5.2 property): one prompt-only solve must pass the
#      STRONGER harness — a strengthened harness that only a harness-reader
#      can pass has smuggled in an undocumented requirement;
#   7. apply: parent harness written; the wt_ twin updated when it was a
#      byte-copy (else flagged for hand-triage); tfim prompt embeds resynced
#      and convergence re-checked. Any post-apply failure RESTORES the
#      original harness.
#
# New tests also create new carvable tfim blocks — the work registry counts
# them automatically; the next backfill run mints them.
#
# Usage:
#   mix run scripts/strengthen_harnesses.exs                   # DRY: the work list
#   mix run scripts/strengthen_harnesses.exs -- --go           # run (PAID: ~2 calls/family)
#   mix run scripts/strengthen_harnesses.exs -- --go --limit 3 # first N families
#   mix run scripts/strengthen_harnesses.exs -- --report       # ledger summary
#
# Ledger: logs/strengthen_harnesses.jsonl (one row per family per attempt).
# Resume: a family whose CURRENT harness sha has a success row is skipped.

alias GenTask.{Config, Cycle, CycleLog, Evaluator, Mutation, Reply, Variations}

defmodule StrengthenHarnesses do
  @moduledoc false

  @measured "logs/semantic_mutants.jsonl"
  @ledger "logs/strengthen_harnesses.jsonl"
  @floor 0.5
  @sm_limit 40

  def main(argv) do
    argv = Enum.drop_while(argv, &(&1 == "--"))

    {opts, _, _} =
      OptionParser.parse(argv, strict: [go: :boolean, report: :boolean, limit: :integer])

    cond do
      opts[:report] -> report()
      opts[:go] -> go(opts)
      true -> dry()
    end
  end

  # ── population ─────────────────────────────────────────────────────────────
  # Ledgered kill rates, best per task, mapped onto the PARENT family harness
  # (wt_X's gold harness is a byte-copy of X_01's — strengthening the parent
  # covers both; the measurement lists them separately).

  # Measurement policy (fixed 2026-07-13 after Kamil's investigation):
  #
  #   * LATEST row per task wins — NOT the max. Max hides regressions and, worse,
  #     it resurrects families that were already fixed: the R10 campaign
  #     (2026-07-09) tightened 11 harnesses and the parents were re-measured
  #     (075_004: 0.00 -> 1.00), but the `wt_` copies were never re-measured, so
  #     their 07-08 rows still read 0.00.
  #   * `wt_` rows are IGNORED. A wt_ dir is a byte-copy of its parent's module +
  #     harness (the embed gates enforce that), so its kill rate is the parent's
  #     by construction — a separate row can only ever be a stale duplicate. It
  #     was exactly such a row that dragged 10 healthy families into last night's
  #     work list.
  #   * A row whose content keys are missing (pre-2026-07-13) or no longer match
  #     the files on disk is STALE-UNKNOWN: it still seeds the work list (a hint,
  #     not a verdict), the loop re-measures live before acting, and the dry list
  #     says so.
  defp weak_parents do
    latest =
      @measured
      |> File.stream!()
      |> Enum.reduce(%{}, fn line, acc ->
        with {:ok, %{"task" => t, "total" => tot} = row} <- JSON.decode(line),
             true <- tot > 0,
             false <- String.starts_with?(t, "wt_") do
          prev = acc[t]

          if prev && prev["ts"] >= row["ts"],
            do: acc,
            else: Map.put(acc, t, row)
        else
          _ -> acc
        end
      end)

    latest
    |> Enum.filter(fn {_t, row} -> row["killed"] / row["total"] < @floor end)
    |> Enum.map(fn {t, row} ->
      {parent_dir(t), row["killed"] / row["total"], row_stale?(t, row)}
    end)
    |> Enum.filter(fn {dir, _, _} -> dir && File.dir?(dir) end)
    |> Enum.reduce(%{}, fn {dir, rate, stale}, acc ->
      Map.update(acc, dir, {rate, stale}, fn {r, s} -> {min(r, rate), s and stale} end)
    end)
    |> Enum.sort_by(fn {_dir, {rate, _}} -> rate end)
  end

  # A row is stale when its content keys are absent (pre-2026-07-13 rows) or no
  # longer match the files on disk.
  defp row_stale?(task, row) do
    dir = Path.join("tasks", task)

    cond do
      not File.dir?(dir) -> true
      is_nil(row["harness_sha"]) or is_nil(row["solution_sha"]) -> true
      true -> row["harness_sha"] != file_sha(dir, "test_harness.exs")
    end
  end

  defp file_sha(dir, name) do
    path = Path.join(dir, name)
    if File.regular?(path), do: CycleLog.content_sha(File.read!(path))
  end

  defp parent_dir("wt_" <> rest), do: hd(Path.wildcard("tasks/#{rest}_01"))

  defp parent_dir(task) do
    if File.dir?(Path.join("tasks", task)), do: Path.join("tasks", task), else: nil
  end

  defp dry do
    parents = weak_parents()
    done = success_shas()

    IO.puts("Semantic-floor work list (< #{@floor} best kill rate), deduped to parents:\n")

    for {dir, {rate, stale}} <- parents do
      status =
        cond do
          MapSet.member?(done, harness_sha(dir)) -> "DONE (this harness already strengthened)"
          stale -> "todo (ledger row STALE — harness changed since; re-measured live)"
          true -> "todo"
        end

      IO.puts("  #{Float.round(rate, 2)}  #{Path.basename(dir)}  #{status}")
    end

    IO.puts(
      "\n#{length(parents)} family(ies); ~2 LLM calls each (strengthen + blind gate) " <>
        "plus local semantic re-measures. Run with `-- --go`."
    )
  end

  # ── the loop ────────────────────────────────────────────────────────────────

  defp go(opts) do
    refuse_if_generate_alive!()
    cfg = Config.new([])
    done = success_shas()

    todo =
      weak_parents()
      |> Enum.reject(fn {dir, _} -> MapSet.member?(done, harness_sha(dir)) end)
      |> then(&if opts[:limit], do: Enum.take(&1, opts[:limit]), else: &1)

    IO.puts("strengthening #{length(todo)} family(ies), sequential, ledger #{@ledger}\n")

    Enum.each(Enum.with_index(todo, 1), fn {{dir, {ledger_rate, _stale}}, i} ->
      IO.write(
        "[#{i}/#{length(todo)}] #{Path.basename(dir)} (ledgered #{Float.round(ledger_rate, 2)}) ... "
      )

      row = strengthen(cfg, dir)
      append_ledger(row)
      IO.puts("#{row.verdict}#{if row[:detail], do: " — " <> row.detail, else: ""}")
    end)

    report()
  end

  defp strengthen(cfg, dir) do
    id = Path.basename(dir)
    prompt = File.read!(Path.join(dir, "prompt.md"))
    solution = File.read!(Path.join(dir, "solution.ex"))
    harness0 = File.read!(Path.join(dir, "test_harness.exs"))
    manifest = read_optional(Path.join(dir, "manifest.exs"))

    base = %{family: id, harness_sha_before: CycleLog.content_sha(harness0), ts: now()}

    {rate0, survivors} = measure(cfg, id, prompt, solution, harness0, manifest)

    cond do
      rate0 >= @floor ->
        Map.merge(base, %{
          verdict: :already_ok,
          rate_before: rate0,
          rate_after: rate0,
          harness_sha_after: base.harness_sha_before
        })

      survivors == [] ->
        Map.merge(base, %{verdict: :no_survivors_enumerated, rate_before: rate0})

      true ->
        attempt_strengthen(
          cfg,
          dir,
          id,
          prompt,
          solution,
          harness0,
          manifest,
          rate0,
          survivors,
          base
        )
    end
  end

  defp attempt_strengthen(
         cfg,
         dir,
         id,
         prompt,
         solution,
         harness0,
         manifest,
         rate0,
         survivors,
         base
       ) do
    with {:ok, harness1} <- gen_stronger(cfg, id, prompt, solution, harness0, survivors),
         :ok <- add_only(harness0, harness1),
         {:ok, json} <- grade_green(cfg, id, prompt, solution, harness1, manifest),
         :ok <- lints(json, prompt, solution, harness1),
         :ok <- whole_mutant_killed(cfg, id, prompt, solution, harness1, manifest),
         {rate1, _} = measure(cfg, id, prompt, solution, harness1, manifest),
         :ok <- floor_reached(rate0, rate1),
         :ok <- blind_gate(cfg, id, prompt, harness0, harness1, manifest) do
      apply_result = apply!(dir, harness0, harness1)

      Map.merge(base, %{
        verdict: apply_result,
        rate_before: rate0,
        rate_after: rate1,
        tests_added: length(test_blocks(harness1)) - length(test_blocks(harness0)),
        harness_sha_after: CycleLog.content_sha(harness1)
      })
    else
      {:error, why} ->
        Map.merge(base, %{verdict: :rejected, rate_before: rate0, detail: why})
    end
  end

  # ── gates ───────────────────────────────────────────────────────────────────

  defp gen_stronger(cfg, id, prompt, solution, harness, survivors) do
    system =
      "You are a senior Elixir engineer hardening an ExUnit test suite. You reply with " <>
        "ONLY a single <file path=\"test_harness.exs\">…</file> block containing the " <>
        "complete new harness, nothing else."

    user = """
    This harness misses first-order behavior changes: each SURVIVOR below is a
    one-token mutation of the reference solution that every current test passes.

    ADD tests that kill them, under hard rules:
    - ADD ONLY: every existing test block must remain byte-for-byte identical
      (they are carved into derived tasks); no renames, no edits, no deletions.
    - Every new assertion must be justified by an explicit statement in the
      task prompt below — never assert undocumented behavior, internal state,
      or exact error message text (assert the exception TYPE only).
    - Same conventions as the existing harness (`use ExUnit.Case, async: false`,
      no `ExUnit.start()`, self-contained, ZERO compile warnings, lines ≤ 98
      columns, process-unique temp paths via `System.pid()` +
      `System.unique_integer/1` where needed).
    - Prefer few, sharp tests over many shallow ones; name each test for the
      behavior it pins.

    === SURVIVING MUTANTS (kill these) ===
    #{Enum.map_join(survivors, "\n", &("  - " <> &1))}

    === task prompt.md ===
    #{prompt}

    === reference solution.ex ===
    #{solution}

    === current test_harness.exs ===
    #{harness}
    """

    case Cycle.opus(cfg, id, "strengthen_harness", system, user) do
      {:ok, text, _meta} ->
        case Reply.parse(text) do
          %{"test_harness.exs" => h} when is_binary(h) and h != "" ->
            # Canonicalize before any gate runs: a model-written harness is not
            # formatter-canonical, and the corpus format gate would reject it at
            # push time long after the (correct) content decision (found on the
            # first applied family, 002_003). Formatting cannot change behavior;
            # every gate below still runs on the exact bytes that get written.
            {:ok, canonicalize(h)}

          _ ->
            {:error, "reply carried no test_harness.exs block"}
        end

      {:error, reason} ->
        {:error, "strengthen call failed: #{inspect(reason)}"}
    end
  end

  # `mix format` output with the repo's trailing-newline convention.
  defp canonicalize(src) do
    src
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> String.trim_trailing("\n")
    |> Kernel.<>("\n")
  rescue
    _ -> src
  end

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
    json = grade(cfg, id, prompt, solution, harness, manifest, "solution.ex")

    cond do
      not Evaluator.green?({:ok, json}) ->
        {:error, "reference not green vs new harness: " <> Cycle.reason_for({:ok, json})}

      (json["compile_warnings"] || 0) > 0 ->
        {:error, "new harness compiles with warnings: #{inspect(json["warning_details"])}"}

      true ->
        {:ok, json}
    end
  end

  defp lints(json, prompt, solution, harness) do
    files = %{"prompt.md" => prompt, "solution.ex" => solution, "test_harness.exs" => harness}

    case Evaluator.quality_shortfall(json, files) do
      nil -> :ok
      shortfall -> {:error, "house/harness lint: " <> shortfall}
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

  defp floor_reached(rate0, rate1) do
    cond do
      rate1 < @floor ->
        {:error, "still below floor after strengthening (#{Float.round(rate1, 2)})"}

      rate1 < rate0 ->
        {:error, "kill rate went DOWN (#{Float.round(rate0, 2)} → #{Float.round(rate1, 2)})"}

      true ->
        :ok
    end
  end

  # The blind gate can fail for TWO different reasons and they demand opposite
  # conclusions (found 2026-07-13 on 063_004, whose blind solve failed the
  # harness's ORIGINAL tests — the added tests were innocent):
  #
  #   * failures land on ADDED tests  -> the harness over-specifies: it pins
  #     behavior the prompt does not state. Rejecting is right, and the fix is
  #     the PROMPT (scripts/enrich_prompts.exs).
  #   * failures land on PRE-EXISTING tests -> the blind solver simply could not
  #     solve the task this attempt (hard concurrency/timing families). That says
  #     nothing about the added tests. Still reject (we cannot prove the added
  #     tests are blind-passable), but label it honestly so nobody "fixes" a
  #     prompt that is not broken.
  defp blind_gate(cfg, id, prompt, harness0, harness1, manifest) do
    case Variations.blind_solution("strengthen_blind_#{id}", prompt, cfg) do
      {:ok, blind} ->
        json = grade(cfg, id, prompt, blind, harness1, manifest, "solution.ex")

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
            not (json["compiled"] == true) ->
              {:error,
               "blind solve did not COMPILE (solver defect, not a prompt or harness " <>
                 "finding) — retry the family"}

            added == [] and pre_existing != [] ->
              {:error,
               "INCONCLUSIVE: the blind solver failed the harness's ORIGINAL tests " <>
                 "(#{Enum.join(Enum.take(pre_existing, 3), "; ")}) — the solver could not " <>
                 "solve this task, which says nothing about the added tests. Do NOT enrich " <>
                 "the prompt on this evidence; retry the family."}

            true ->
              {:error,
               "blind solver fails ADDED test(s) — the harness pins behavior the prompt " <>
                 "does not state. Failing: " <> Enum.join(Enum.take(added, 4), "; ")}
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

  # ExUnit reports "test <name>" (and "test <describe> <name>" for nested blocks).
  defp normalize_test_name(nil), do: ""

  defp normalize_test_name(t) do
    t |> to_string() |> String.replace_prefix("test ", "") |> String.trim()
  end

  # ── apply + propagate (restore on any failure) ──────────────────────────────

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
      # tfim resync failed (a carved gold no longer locates?) — restore everything.
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

  # ── measurement + grading plumbing ──────────────────────────────────────────

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
    {if(total > 0, do: killed / total, else: 1.0), Enum.reverse(survivors)}
  end

  defp grade(cfg, id, prompt, solution, harness, manifest, _sol_name) do
    dir = stage(cfg, id, prompt, solution, harness, manifest)

    case Evaluator.grade(dir, cfg) do
      {:ok, json} -> json
      :timeout_or_crash -> %{"compiled" => false, "tests_failed" => 0, "tests_errors" => 0}
    end
  end

  defp grade_override(cfg, id, prompt, solution, harness, manifest, override_src) do
    dir = stage(cfg, id, prompt, solution, harness, manifest)
    path = Path.join(System.tmp_dir!(), "strn_#{System.unique_integer([:positive])}.ex")
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

    Evaluator.stage!(Path.join(cfg.staging_dir, "strengthen_#{id}"), files)
  end

  # ── ledger / report / misc ──────────────────────────────────────────────────

  defp append_ledger(row) do
    File.mkdir_p!("logs")
    File.write!(@ledger, JSON.encode!(row) <> "\n", [:append])
  end

  defp success_shas do
    case File.read(@ledger) do
      {:ok, body} ->
        body
        |> String.split("\n", trim: true)
        |> Enum.reduce(MapSet.new(), fn line, acc ->
          case JSON.decode(line) do
            {:ok, %{"verdict" => v, "harness_sha_after" => sha}}
            when v in ["applied", "applied_wt_divergent", "already_ok"] and is_binary(sha) ->
              MapSet.put(acc, sha)

            _ ->
              acc
          end
        end)

      _ ->
        MapSet.new()
    end
  end

  defp report do
    case File.read(@ledger) do
      {:ok, body} ->
        rows =
          body
          |> String.split("\n", trim: true)
          |> Enum.map(&JSON.decode!/1)

        freq = Enum.frequencies_by(rows, & &1["verdict"])
        IO.puts("\n=== STRENGTHEN LEDGER (#{length(rows)} row(s)) === #{inspect(freq)}")

        for r <- rows, r["verdict"] in ["applied", "applied_wt_divergent"] do
          IO.puts(
            "  #{r["family"]}: #{r["rate_before"] && Float.round(r["rate_before"] * 1.0, 2)} → " <>
              "#{r["rate_after"] && Float.round(r["rate_after"] * 1.0, 2)} " <>
              "(+#{r["tests_added"]} test(s))#{if r["verdict"] == "applied_wt_divergent", do: "  [wt_ divergent — hand-triage]", else: ""}"
          )
        end

      _ ->
        IO.puts("no ledger yet")
    end
  end

  defp harness_sha(dir), do: CycleLog.content_sha(File.read!(Path.join(dir, "test_harness.exs")))

  defp read_optional(path), do: if(File.regular?(path), do: File.read!(path))

  defp now, do: DateTime.utc_now() |> DateTime.to_iso8601()

  # Writes into tasks/ — never concurrently with a generation loop (same guard
  # contract as resync_embeds.exs).
  defp refuse_if_generate_alive! do
    {out, _} = System.cmd("pgrep", ["-af", "beam.smp"], stderr_to_stdout: true)

    if String.contains?(out, "generate.exs") do
      IO.puts("REFUSING --go: a generation loop (generate.exs) is alive.")
      System.halt(1)
    end
  end
end

StrengthenHarnesses.main(System.argv())
