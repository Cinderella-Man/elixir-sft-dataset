# rewrite_reachins.exs — S9 grandfathered reach-in purge (T2.1; design docs/13 §1.7).
#
# 24 April-era root harnesses call `:sys.get_state`/`:sys.replace_state`. Two idioms:
#   * BARRIER — the return value is discarded; the call only synchronizes with the
#     GenServer after an async `send` (the 004_x `tick/1` helper). Replace with any
#     DOCUMENTED synchronous public call through the same server queue.
#   * STATE-ASSERT — the return value is asserted on: the test pins internal state
#     shape instead of observable behavior. Replace with assertions through the
#     documented public API (injected clocks/hooks count as documented).
#
# Unlike strengthen_harnesses (ADD-only), this tool REWRITES existing blocks — the
# one thing the add-only rule exists to prevent — so it owns the re-carve path:
# a rewritten block whose text is carved into a tfim child re-produces that child's
# gold through the carver's own rules (raw block slice, ≤98 columns, isolation-kill)
# or PARKS the child for hand triage. It never deletes a child (Kamil's call).
#
# Per family (ledgered, resumable, restore-on-failure):
#   1. locate offending test blocks + helpers (regex);
#   2. one LLM call rewrites ONLY the offending code — same test names, untouched
#      test blocks byte-identical, zero `:sys.` anywhere after;
#   3. reference green + zero warnings + house lints (S9 is a hard shortfall there,
#      so the purge is machine-checked twice);
#   4. whole-module raise-mutant still killed; every REWRITTEN block passes the
#      carver's isolation-kill gate (green alone + kills a per-function mutant —
#      a rewrite must not leave a vacuous test);
#   5. semantic re-measure: rate must not DROP (a reach-in pinned something; its
#      observable replacement must pin at least as much);
#   6. BLIND gate — one prompt-only solve passes the rewritten harness; failures
#      attributed to rewritten vs untouched tests (docs/14 rule 10 applies);
#   7. apply parent + wt_ byte-copy twin, resync tfim prompt embeds, re-carve
#      affected golds in place (or park), append gate-sha-stamped ledger row.
#
# Usage:
#   mix run scripts/rewrite_reachins.exs                    # DRY: work list
#   mix run scripts/rewrite_reachins.exs -- --go --only "004_001*"   # pilot
#   mix run scripts/rewrite_reachins.exs -- --go            # fleet (PAID)
#   mix run scripts/rewrite_reachins.exs -- --report        # ledger summary
#
# Ledger: logs/rewrite_reachins.jsonl. Resume: a family whose CURRENT harness sha
# has a success row is skipped (and a purged family no longer greps in anyway).

alias GenTask.{Config, Cycle, CycleLog, Evaluator, Mutation, Reply, TestFim, Variations}

defmodule RewriteReachins do
  @moduledoc false

  @ledger "logs/rewrite_reachins.jsonl"
  @measured "logs/semantic_mutants.jsonl"
  @reachin ~r/:sys\.(get_state|replace_state)/
  @sm_limit 40

  def main(argv) do
    argv = Enum.drop_while(argv, &(&1 == "--"))

    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [go: :boolean, report: :boolean, limit: :integer, only: :string]
      )

    cond do
      opts[:report] -> report()
      opts[:go] -> go(opts)
      true -> dry(opts)
    end
  end

  # ── population (live grep — a purged family self-removes) ──────────────────

  defp offenders do
    Path.wildcard("tasks/[0-9]*_01")
    |> Enum.filter(&File.regular?(Path.join(&1, "test_harness.exs")))
    |> Enum.map(fn dir -> {dir, File.read!(Path.join(dir, "test_harness.exs"))} end)
    |> Enum.filter(fn {_dir, h} -> Regex.match?(@reachin, h) end)
    |> Enum.sort()
  end

  defp filter_only(dirs, opts) do
    Enum.filter(dirs, fn {dir, _} -> match_only?(Path.basename(dir), opts[:only]) end)
  end

  defp match_only?(_f, nil), do: true

  defp match_only?(f, globs) do
    globs
    |> String.split(",", trim: true)
    |> Enum.any?(fn g ->
      re = g |> String.trim() |> Regex.escape() |> String.replace("\\*", ".*")
      Regex.match?(~r/#{re}/, f)
    end)
  end

  defp dry(opts) do
    done = success_shas()

    IO.puts("S9 reach-in work list (live grep over root harnesses):\n")

    rows =
      for {dir, harness} <- filter_only(offenders(), opts) do
        id = Path.basename(dir)
        blocks = offending_blocks(harness)
        outside = outside_block_hits(harness)
        affected = affected_children(id, blocks)

        status =
          if MapSet.member?(done, CycleLog.content_sha(harness)),
            do: "DONE (this harness already rewritten)",
            else: "todo"

        IO.puts(
          "  #{id}: #{count_hits(harness)} call(s) — #{length(blocks)} block(s), " <>
            "#{length(outside)} helper line(s), #{length(affected)} tfim gold(s) — #{status}"
        )

        {dir, status}
      end

    todo = Enum.count(rows, fn {_, s} -> s == "todo" end)
    IO.puts("\n#{todo} family(ies) to rewrite; ~2 LLM calls each. Run with `-- --go`.")
  end

  defp count_hits(harness), do: length(Regex.scan(@reachin, harness))

  # ── the loop ────────────────────────────────────────────────────────────────

  defp go(opts) do
    refuse_if_generate_alive!()
    cfg = Config.new([])
    done = success_shas()

    todo =
      offenders()
      |> filter_only(opts)
      |> Enum.reject(fn {_dir, h} -> MapSet.member?(done, CycleLog.content_sha(h)) end)
      |> then(&if opts[:limit], do: Enum.take(&1, opts[:limit]), else: &1)

    IO.puts("rewriting #{length(todo)} family(ies), sequential, ledger #{@ledger}\n")

    Enum.each(Enum.with_index(todo, 1), fn {{dir, harness0}, i} ->
      IO.write("[#{i}/#{length(todo)}] #{Path.basename(dir)} ... ")
      row = rewrite(cfg, dir, harness0)
      append_ledger(row)
      IO.puts("#{row.verdict}#{if row[:detail], do: " — " <> row.detail, else: ""}")
    end)

    report()
  end

  defp rewrite(cfg, dir, harness0) do
    id = Path.basename(dir)
    prompt = File.read!(Path.join(dir, "prompt.md"))
    solution = File.read!(Path.join(dir, "solution.ex"))
    manifest = read_optional(Path.join(dir, "manifest.exs"))

    base = %{
      family: id,
      harness_sha_before: CycleLog.content_sha(harness0),
      gate_sha: gate_sha(),
      ts: now()
    }

    blocks = offending_blocks(harness0)
    {rate0, _surv0, _k0, _t0} = measure(cfg, id, prompt, solution, harness0, manifest)

    with {:ok, harness1} <- gen_rewrite(cfg, id, prompt, solution, harness0, blocks),
         :ok <- rewrite_only(harness0, harness1, blocks),
         {:ok, json} <- grade_green(cfg, id, prompt, solution, harness1, manifest),
         {:ok, count_debt} <- lints(json, prompt, solution, harness1),
         :ok <- whole_mutant_killed(cfg, id, prompt, solution, harness1, manifest),
         :ok <- rewritten_blocks_kill(cfg, id, solution, harness1, blocks),
         {rate1, surv1, k1, t1} = measure(cfg, id, prompt, solution, harness1, manifest),
         :ok <- no_drop(rate0, rate1),
         :ok <- blind_gate(cfg, id, prompt, harness0, harness1, manifest, blocks) do
      {apply_result, recarve} = apply!(cfg, dir, harness0, harness1, blocks)

      if apply_result in [:applied, :applied_wt_divergent],
        do: record_measurement(dir, id, k1, t1, surv1)

      Map.merge(base, %{
        verdict: apply_result,
        rate_before: rate0,
        rate_after: rate1,
        blocks_rewritten: Enum.map(blocks, & &1.qual),
        recarve: recarve,
        count_shortfall: count_debt,
        harness_sha_after: CycleLog.content_sha(harness1)
      })
    else
      {:error, why} ->
        Map.merge(base, %{verdict: :rejected, rate_before: rate0, detail: why})
    end
  end

  # ── offending-code discovery ────────────────────────────────────────────────

  # Carvable blocks whose text contains a reach-in, tagged with their qualified
  # name and raw slice (the carver's gold view of the same lines).
  defp offending_blocks(harness) do
    lines = String.split(harness, "\n")

    for cand <- TestFim.carvable_blocks(harness),
        src = lines |> Enum.slice(cand.s..cand.e) |> Enum.join("\n"),
        Regex.match?(@reachin, src) do
      %{qual: TestFim.qual(cand), name: cand.name, src: src}
    end
  end

  # Reach-in lines living OUTSIDE carvable blocks (setup, defp helpers — the
  # 004_x barrier idiom). Reported for the prompt; the zero-reach-in rule
  # covers their removal.
  defp outside_block_hits(harness) do
    lines = String.split(harness, "\n")

    in_block =
      TestFim.carvable_blocks(harness)
      |> Enum.flat_map(fn c -> Enum.to_list(c.s..c.e) end)
      |> MapSet.new()

    for {line, idx} <- Enum.with_index(lines),
        Regex.match?(@reachin, line),
        not MapSet.member?(in_block, idx),
        do: {idx, String.trim(line)}
  end

  # ── the rewrite call + mechanical validation ───────────────────────────────

  defp gen_rewrite(cfg, id, prompt, solution, harness, blocks) do
    outside = outside_block_hits(harness)

    system =
      "You are a senior Elixir engineer removing test anti-patterns. You reply with " <>
        "ONLY a single <file path=\"test_harness.exs\">…</file> block containing the " <>
        "complete new harness, nothing else."

    user = """
    This harness reaches into GenServer internals via `:sys.get_state`/
    `:sys.replace_state`. Remove EVERY such call, under hard rules:

    - Two idioms, two fixes:
      * BARRIER (return value discarded — it only waits until the server has
        processed a prior async message): replace with a synchronous call to a
        PUBLIC API function documented in the task prompt below. Any
        `GenServer.call`-backed function works as the barrier; pick the most
        natural read-only one. Keep the helper's name and arity if it is a
        helper.
      * STATE-ASSERT (return value inspected/asserted): re-express the test
        through observable behavior documented in the prompt — public API
        return values, injected clock/random hooks (they are documented), or
        messages the prompt promises. If the prompt documents no observable
        channel for some assertion, assert the closest DOCUMENTED consequence
        instead; never invent an undocumented one.
    - REWRITE ONLY the code that needs it: every test block that contains no
      reach-in must remain byte-for-byte identical (they are carved into
      derived tasks). Keep every test and describe NAME exactly as it is —
      renames break derived-task bookkeeping.
    - Never assert internal state, exact error-message text, or `inspect`
      output; never send undocumented messages; never add `Process.sleep`.
    - Comments must describe BEHAVIOR, never the editing process: a hard lint
      rejects comments citing the prompt, `--- added/changed` banners, or
      repair markers.
    - Same conventions as the existing harness (`use ExUnit.Case, async: false`,
      no `ExUnit.start()`, self-contained, ZERO compile warnings, lines ≤ 98
      columns).

    === OFFENDING TEST BLOCKS (rewrite these, keep their names) ===
    #{Enum.map_join(blocks, "\n", &("  - " <> &1.qual))}

    === REACH-INS OUTSIDE TEST BLOCKS (helpers/setup — rewrite these lines' code) ===
    #{if outside == [], do: "  (none)", else: Enum.map_join(outside, "\n", fn {i, l} -> "  line #{i + 1}: #{l}" end)}

    === task prompt.md ===
    #{prompt}

    === reference solution.ex ===
    #{solution}

    === current test_harness.exs ===
    #{harness}
    """

    case Cycle.opus(cfg, id, "rewrite_reachins", system, user) do
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
        {:error, "rewrite call failed: #{inspect(reason)}"}
    end
  end

  # Keep every rewrite candidate for review: a rejection's ledger row holds only
  # the failing gate's message, and judging WHAT the model produced (rule-9
  # pilot review, blind-gate triage) needs the full source. Keyed by the
  # harness-before sha so retries against the same harness overwrite, while a
  # later harness gets its own file.
  defp save_candidate(id, harness_before, candidate) do
    dir = "logs/rewrite_candidates"
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

  # The rewrite counterpart of strengthen's add-only rule: zero reach-ins remain,
  # the qualified test-name set is unchanged, and every block that had NO
  # reach-in survives byte-verbatim.
  defp rewrite_only(harness0, harness1, offending) do
    offending_names = MapSet.new(offending, & &1.qual)
    lines0 = String.split(harness0, "\n")

    untouched_blocks =
      for cand <- TestFim.carvable_blocks(harness0),
          not MapSet.member?(offending_names, TestFim.qual(cand)),
          do: lines0 |> Enum.slice(cand.s..cand.e) |> Enum.join("\n")

    names0 = harness0 |> TestFim.carvable_blocks() |> Enum.map(&TestFim.qual/1) |> Enum.sort()
    names1 = harness1 |> TestFim.carvable_blocks() |> Enum.map(&TestFim.qual/1) |> Enum.sort()

    missing = Enum.reject(untouched_blocks, &String.contains?(harness1, &1))

    cond do
      Regex.match?(@reachin, harness1) ->
        {:error, "reach-in survives the rewrite"}

      names1 != names0 ->
        {:error,
         "test-name set changed: " <>
           inspect({names0 -- names1, names1 -- names0}, limit: 6, printable_limit: 200)}

      missing != [] ->
        {:error, "modified #{length(missing)} test block(s) that had no reach-in"}

      true ->
        :ok
    end
  end

  # ── gates (grade/lints/mutants shared shape with strengthen_harnesses) ─────

  defp grade_green(cfg, id, prompt, solution, harness, manifest) do
    json = grade(cfg, id, prompt, solution, harness, manifest)

    cond do
      not Evaluator.green?({:ok, json}) ->
        {:error, "reference not green vs rewritten harness: " <> Cycle.reason_for({:ok, json})}

      (json["compile_warnings"] || 0) > 0 ->
        {:error, "rewritten harness compiles with warnings: #{inspect(json["warning_details"])}"}

      true ->
        {:ok, json}
    end
  end

  # The min-test-count floor is TODAY'S accept standard; four grandfathered
  # harnesses never met it, and this tool is forbidden to add tests (the
  # name-set-unchanged rule) — so that ONE shortfall cannot be allowed to block
  # the reach-in purge. It is returned as a flag and recorded in the ledger row
  # instead (closing it is strengthen/T1.4 scope, a separate register item).
  # Every other shortfall stays a hard reject.
  @count_shortfall ~r/^only \d+ test\(s\) — the harness needs at least/

  defp lints(json, prompt, solution, harness) do
    files = %{"prompt.md" => prompt, "solution.ex" => solution, "test_harness.exs" => harness}

    case Evaluator.quality_shortfall(json, files) do
      nil ->
        {:ok, false}

      shortfall ->
        {count_debt, real} =
          shortfall
          |> String.split("; ")
          |> Enum.split_with(&Regex.match?(@count_shortfall, &1))

        if real == [],
          do: {:ok, count_debt != []},
          else: {:error, "house/harness lint: " <> Enum.join(real, "; ")}
    end
  end

  defp whole_mutant_killed(cfg, id, prompt, solution, harness, manifest) do
    mutant = Mutation.mutate(solution)
    json = grade_override(cfg, id, prompt, solution, harness, manifest, mutant)
    grade = {:ok, json}

    if Evaluator.killed_by_tests?(grade) or Evaluator.errored_against_mutant?(grade),
      do: :ok,
      else: {:error, "whole-module raise-mutant SURVIVES the rewritten harness"}
  end

  # Each rewritten block must pass the carver's isolation-kill gate: run alone
  # (plus setup/helpers) it is green AND kills at least one per-function raise
  # mutant. This is the anti-vacuity check AND the re-carve pre-flight.
  defp rewritten_blocks_kill(cfg, id, solution, harness1, offending) do
    offending_names = MapSet.new(offending, & &1.qual)

    targets =
      harness1
      |> TestFim.carvable_blocks()
      |> Enum.filter(&MapSet.member?(offending_names, TestFim.qual(&1)))

    iso_dir = Path.join(Config.new([]).staging_dir, "rewrite_iso_#{id}")

    Enum.reduce_while(targets, :ok, fn cand, :ok ->
      iso = TestFim.isolate_for_test(harness1, cand)

      case Mutation.gate_isolation(iso_dir, solution, iso, cfg) do
        :killed ->
          {:cont, :ok}

        other ->
          {:halt,
           {:error,
            "rewritten block #{inspect(TestFim.qual(cand))} fails isolation gate " <>
              "(#{inspect(other)}) — vacuous or dependent rewrite"}}
      end
    end)
  end

  defp no_drop(rate0, rate1) do
    if rate1 >= rate0,
      do: :ok,
      else:
        {:error,
         "semantic kill rate DROPPED (#{Float.round(rate0, 2)} → #{Float.round(rate1, 2)}) — " <>
           "the observable rewrite pins less than the reach-in did; hand work"}
  end

  # Same two-way attribution as strengthen's blind gate, adapted: failures on
  # REWRITTEN tests may mean the rewrite pins undocumented behavior; failures on
  # untouched tests say the solver could not solve the task (says nothing about
  # the rewrite). Rule 10 applies to both.
  defp blind_gate(cfg, id, prompt, _harness0, harness1, manifest, offending) do
    case Variations.blind_solution("rewrite_blind_#{id}", prompt, cfg) do
      {:ok, blind} ->
        json = grade(cfg, id, prompt, blind, harness1, manifest)

        if Evaluator.green?({:ok, json}) do
          :ok
        else
          rewritten = MapSet.new(offending, & &1.name)

          failing =
            (json["test_failures"] || [])
            |> Enum.map(&normalize_test_name(&1["test"]))
            |> Enum.reject(&(&1 == ""))

          {on_rewritten, on_untouched} =
            Enum.split_with(failing, fn f ->
              Enum.any?(rewritten, &String.contains?(f, &1))
            end)

          cond do
            json["compiled"] != true ->
              {:error, "blind solve did not COMPILE (solver defect) — retry the family"}

            on_rewritten == [] and on_untouched != [] ->
              {:error,
               "INCONCLUSIVE: blind solver failed only UNTOUCHED tests " <>
                 "(#{Enum.join(Enum.take(on_untouched, 3), "; ")}) — solver-weak this " <>
                 "attempt; retry the family"}

            true ->
              {:error,
               "blind solver fails REWRITTEN test(s) — either the rewrite pins " <>
                 "undocumented behavior (hand-check the prompt) or the solver got " <>
                 "documented behavior wrong (rule 10). Failing: " <>
                 Enum.join(Enum.take(on_rewritten, 4), "; ")}
          end
        end

      {:error, reason} ->
        {:error, "blind solve call failed: #{inspect(reason)}"}
    end
  end

  defp normalize_test_name(nil), do: ""

  defp normalize_test_name(t) do
    t |> to_string() |> String.replace_prefix("test ", "") |> String.trim()
  end

  # ── apply + wt twin + tfim resync + re-carve (restore on failure) ──────────

  defp apply!(cfg, dir, harness0, harness1, offending) do
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
      recarve = recarve_children!(cfg, id, harness0, harness1, offending)
      verdict = if wt_status == :divergent_hand_triage, do: :applied_wt_divergent, else: :applied
      {verdict, recarve}
    else
      File.write!(harness_path, harness0)
      if wt_status == :updated, do: File.write!(Path.join(wt, "test_harness.exs"), harness0)
      {:reverted_tfim_resync_failed, []}
    end
  end

  defp wt_twin(id) do
    base = String.replace_suffix(id, "_01", "")

    case Path.wildcard("tasks/wt_#{base}") do
      [dir] -> dir
      _ -> nil
    end
  end

  # A tfim child is affected iff its gold is one of the REWRITTEN blocks. The
  # new gold is the carver's view of the same block in the new harness: the raw
  # line slice (docs/14 §5.0b — golds are never blanket-propagated), which must
  # honor the ≤98-column mint rule and leave the child grading perfect. Any
  # failure parks the child (`:orphaned`) — never deletes it.
  defp recarve_children!(cfg, id, harness0, harness1, offending) do
    offending_names = MapSet.new(offending, & &1.qual)
    base = String.replace_suffix(id, "_01", "")
    lines0 = String.split(harness0, "\n")
    lines1 = String.split(harness1, "\n")

    old_by_qual =
      for cand <- TestFim.carvable_blocks(harness0),
          MapSet.member?(offending_names, TestFim.qual(cand)),
          into: %{},
          do: {TestFim.qual(cand), lines0 |> Enum.slice(cand.s..cand.e) |> Enum.join("\n")}

    new_by_qual =
      for cand <- TestFim.carvable_blocks(harness1),
          MapSet.member?(offending_names, TestFim.qual(cand)),
          into: %{},
          do: {TestFim.qual(cand), lines1 |> Enum.slice(cand.s..cand.e) |> Enum.join("\n")}

    recarved =
      for child <- Path.wildcard("tasks/tfim_#{base}_*"),
          gold0 = File.read!(Path.join(child, "solution.ex")),
          {qual, _old} <-
            Enum.filter(old_by_qual, fn {_q, old} -> String.trim(gold0) == String.trim(old) end) do
        recarve_one(cfg, child, qual, Map.fetch!(new_by_qual, qual), gold0)
      end

    # Safety net for the mapping itself: a gold that was hand-edited after its
    # carve (docs/14 §5.0b — shortened comments) no longer trim-matches any old
    # block, so it dodges the loop above. Any gold still carrying a reach-in
    # after this pass is an unmapped orphan — parked, loudly.
    unmapped =
      for child <- Path.wildcard("tasks/tfim_#{base}_*"),
          gold = File.read!(Path.join(child, "solution.ex")),
          Regex.match?(@reachin, gold),
          do: %{child: Path.basename(child), block: nil, outcome: :orphaned_unmapped}

    recarved ++ unmapped
  end

  defp recarve_one(cfg, child, qual, gold1, gold0) do
    over_98 = gold1 |> String.split("\n") |> Enum.count(&(String.length(&1) > 98))
    File.write!(Path.join(child, "solution.ex"), gold1)

    cond do
      over_98 > 0 ->
        File.write!(Path.join(child, "solution.ex"), gold0)
        %{child: Path.basename(child), block: qual, outcome: :orphaned_over_98}

      not Evaluator.green?(Evaluator.grade(child, cfg)) ->
        File.write!(Path.join(child, "solution.ex"), gold0)
        %{child: Path.basename(child), block: qual, outcome: :orphaned_not_green}

      true ->
        %{child: Path.basename(child), block: qual, outcome: :recarved}
    end
  end

  # ── measurement + grading plumbing (strengthen's, verbatim shape) ───────────

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

    File.write!(@measured, JSON.encode!(row) <> "\n", [:append])
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
        "rwri_#{System.pid()}_#{System.unique_integer([:positive])}.ex"
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

    Evaluator.stage!(Path.join(cfg.staging_dir, "rewrite_#{id}"), files)
  end

  # ── affected-children lookup (dry mode) ─────────────────────────────────────

  defp affected_children(id, blocks) do
    base = String.replace_suffix(id, "_01", "")
    srcs = Enum.map(blocks, &String.trim(&1.src))

    for child <- Path.wildcard("tasks/tfim_#{base}_*"),
        gold = File.read!(Path.join(child, "solution.ex")),
        String.trim(gold) in srcs,
        do: Path.basename(child)
  end

  # ── ledger / report / misc ──────────────────────────────────────────────────

  defp gate_sha, do: CycleLog.gate_sha([Mutation, Evaluator, TestFim])

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
            when v in ["applied", "applied_wt_divergent"] and is_binary(sha) ->
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
        rows = body |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)
        freq = Enum.frequencies_by(rows, & &1["verdict"])
        IO.puts("\n=== REWRITE LEDGER (#{length(rows)} row(s)) === #{inspect(freq)}")

        for r <- rows, r["verdict"] in ["applied", "applied_wt_divergent"] do
          parked = Enum.reject(r["recarve"] || [], &(&1["outcome"] == "recarved"))

          IO.puts(
            "  #{r["family"]}: #{fmt(r["rate_before"])} → #{fmt(r["rate_after"])} " <>
              "(#{length(r["blocks_rewritten"] || [])} block(s), " <>
              "#{length(r["recarve"] || [])} re-carve(s)" <>
              "#{if parked != [], do: ", PARKED: " <> inspect(parked), else: ""})"
          )
        end

      _ ->
        IO.puts("no ledger yet")
    end
  end

  defp fmt(nil), do: "?"
  defp fmt(r), do: Float.round(r * 1.0, 2)

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

RewriteReachins.main(System.argv())
