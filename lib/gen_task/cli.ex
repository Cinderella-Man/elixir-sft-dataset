defmodule GenTask.CLI do
  @moduledoc """
  Entry point for `scripts/generate.exs` (see `docs/04-task-generation-loop.md` §4, §16).

  `main/1` resolves the run config, captures an in-memory catalog snapshot, and drives
  the two sequential work-lists — **catch-up first, then new ground**:

    1. **backfill** — existing accepted `_01`s that lack any registered work
       (`GenTask.Work`) get exactly the missing derivatives;
    2. **new bases** — each todo idea is generated, and only if accepted are its
       variations and FIM subtasks chained from it.

  Both lists are recomputed from disk on every run and every step is idempotent, so
  the plain `mix run scripts/generate.exs` invocation repeatedly converges: it first
  brings the existing record up to date, then progresses to new ideas.

  Each item is wrapped in a rescue so one failure never kills the loop. Terminal
  progress is printed with `IO.puts` (`run_all.exs` style); full prompts/responses go
  only to the per-cycle log files. `plan/1` (pure enumeration) is exposed so the
  work-list can be inspected without any `claude` call.
  """

  require Logger

  alias GenTask.{Base, Catalog, Config, CycleLog, Fim, Mutation, Variations, Work}

  @doc "Run the generation loop from `argv` + the process environment."
  @spec main([String.t()]) :: :ok
  def main(argv) do
    cfg = Config.new(argv)
    CycleLog.startup(cfg)

    # --force: wipe the single requested family BEFORE planning, so the planner
    # sees the idea as todo and the run regenerates it from scratch (T1.9 — the
    # loop-parity probe). Raises without a positional idea number; refuses when
    # the family is not git-clean. Dry-run prints the deletion list only.
    if cfg.force, do: GenTask.Force.wipe!(cfg)

    plan = plan(cfg)
    names = Map.new(plan.ideas, &{&1.num, &1.name})

    print_header(cfg, plan)
    maybe_reconcile(cfg)

    # Catch up the existing record before breaking new ground: backfill first, so a
    # freshly raised cap / new work type is applied corpus-wide before LLM budget is
    # spent on new base ideas.
    run_backfill(plan.backfill, names, cfg)
    run_bases(plan.bases, cfg)

    maybe_mint_repairs(cfg)

    IO.puts("\nDone.")
    :ok
  end

  # Post-run repair minting (docs/12 §5.1 item 7): every graded attempt chain captured
  # this run (and any earlier ones still on disk) is turned into verified repair-pair
  # tasks. `mint_repairs.exs` lives in scripts/ (not compiled into lib/) and the loop
  # runs under `mix run`, so we shell out to a fresh `mix run` subprocess rather than
  # `Code.require`. It is add-only and double-verified, so re-running is safe. A failure
  # of the minting step must NOT fail the run — log and continue. Skipped in dry-run
  # (minting promotes into tasks/, which dry-run must never do).
  defp maybe_mint_repairs(%Config{dry_run: true}) do
    IO.puts("\nRepair minting: skipped (dry-run).")
    :ok
  end

  defp maybe_mint_repairs(%Config{} = _cfg) do
    IO.puts("\nMinting repair tasks from captured attempt chains ...")

    try do
      {out, status} =
        System.cmd("mix", ["run", "scripts/mint_repairs.exs"], stderr_to_stdout: true)

      summary = out |> String.split("\n", trim: true) |> Enum.take(-3) |> Enum.join(" | ")

      if status == 0 do
        IO.puts("  #{summary}")
      else
        IO.puts("  repair minting exited #{status} (continuing) — #{summary}")
        Logger.warning("mint_repairs.exs exited #{status}: #{out}")
      end
    rescue
      e ->
        IO.puts("  repair minting failed (continuing): #{Exception.message(e)}")

        Logger.warning(
          "mint_repairs.exs crashed: " <> Exception.format(:error, e, __STACKTRACE__)
        )
    end

    :ok
  end

  @doc """
  Compute the run's work-lists without performing any generation:
  `%{ideas: [...], bases: [...], backfill: [...]}`.
  """
  @spec plan(Config.t()) :: %{
          ideas: [Catalog.Idea.t()],
          bases: [Catalog.Idea.t()],
          backfill: [Catalog.Seed.t()]
        }
  def plan(%Config{} = cfg) do
    ideas = Catalog.ideas(cfg)
    bases = if cfg.only == :backfill, do: [], else: Catalog.todo_bases(ideas, cfg)

    backfill =
      if cfg.skip_backfill or cfg.only == :bases, do: [], else: Catalog.backfill_seeds(cfg)

    %{ideas: ideas, bases: bases, backfill: backfill}
  end

  # Default-ON (opt out with `GEN_RECONCILE=0`): heal any variation directory whose
  # `tasks.md` entry is missing (crash-orphaned, or discarded by the pre-fix Finding E
  # gap). Insert-only and idempotent, so a normal run keeps the catalog consistent
  # automatically; skipped in dry-run. Done-detection is dir-based, so the loop is
  # correct with or without this.
  defp maybe_reconcile(%Config{reconcile: false}), do: :ok
  defp maybe_reconcile(%Config{dry_run: true}), do: :ok

  defp maybe_reconcile(%Config{} = cfg) do
    case Catalog.reconcile_variations!(cfg) do
      0 ->
        :ok

      n ->
        IO.puts(
          "Reconcile: inserted #{n} missing variation catalog entr#{if n == 1, do: "y", else: "ies"}."
        )
    end
  end

  # ------------------------------------------------------------------
  # Work-list 2: new bases (chained; runs after backfill)
  # ------------------------------------------------------------------

  defp run_bases([], _cfg), do: :ok

  defp run_bases(bases, cfg) do
    n = length(bases)

    bases
    |> Enum.with_index(1)
    |> Enum.each(fn {idea, i} -> run_base_item(idea, "[#{pad(i, n)}/#{n}]", cfg) end)
  end

  defp run_base_item(idea, tag, cfg) do
    cond do
      errored?(cfg, idea.task_id) and not cfg.retry_failed ->
        IO.puts(
          "#{tag} #{idea.task_id} (base) ... SKIPPED (prior failure; GEN_RETRY_FAILED=1 to retry)"
        )

      true ->
        try do
          {ms, out} = timed(fn -> Base.run(idea, cfg) end)
          record_and_print(cfg, tag, out, ms)

          if out.status == :accepted do
            variation_seeds = run_variations(cfg, out.seed)
            seeds = [out.seed | variation_seeds]
            run_fim(cfg, seeds)
            run_derived_works(cfg, seeds)
          end
        rescue
          e ->
            IO.puts("#{tag} #{idea.task_id} (base) ... ERROR (#{Exception.message(e)})")
            Logger.error("base item crashed: " <> Exception.format(:error, e, __STACKTRACE__))
        end
    end
  end

  # ------------------------------------------------------------------
  # Work-list 1: backfill (runs first — catch up before new ground)
  # ------------------------------------------------------------------

  defp run_backfill([], _names, _cfg), do: :ok

  defp run_backfill(seeds, names, cfg) do
    IO.puts("\nBackfill: #{length(seeds)} seed(s) needing derivatives.")

    seeds
    |> Enum.with_index(1)
    |> Enum.each(fn {seed, i} ->
      run_backfill_item(seed, names, "[#{pad(i, length(seeds))}/#{length(seeds)}]", cfg)
    end)
  end

  defp run_backfill_item(seed, names, tag, cfg) do
    try do
      files = read_triplet(seed.dir)
      name = Map.get(names, seed.num, humanize(slug_of(seed.task_id)))
      IO.puts("#{tag} #{seed.task_id} (backfill) ...")

      vacuous? = files != nil and vacuous_seed?(cfg, seed, files)

      variation_seeds =
        if seed.needs_variations? and files do
          base_ref = %{
            num: seed.num,
            name: name,
            slug: slug_of(seed.task_id),
            b: 1,
            task_id: seed.task_id,
            files: files
          }

          run_variations(cfg, base_ref)
        else
          []
        end

      self_seed =
        if files do
          %{
            num: seed.num,
            slug: slug_of(seed.task_id),
            b: seed.b,
            task_id: seed.task_id,
            files: files
          }
        end

      own_fim = if seed.needs_fim? and self_seed, do: [self_seed], else: []
      run_fim(cfg, own_fim ++ variation_seeds)

      # Derived-stage works run for fresh variations unconditionally, but the
      # self-seed only when the registry says something is missing — a gradable-skip
      # (Postgres) seed has 0 missing for every derived work and must not re-attempt
      # un-mintable derivatives (BACKFILL Finding A) — and only when its own harness
      # is NOT vacuous: wt_/tfim_ promote that harness (or its blocks) as GOLD
      # completions, so a harness that can't kill a raise-mutant must never become
      # a training label (docs/10 R3). FIM is not gated here — gate_fim already
      # rejects per-candidate against the same weakness.
      self_derive =
        if self_seed != nil and not vacuous? and
             Enum.any?(Work.derived(cfg), &(&1.missing.(seed, cfg) > 0)),
           do: [self_seed],
           else: []

      if vacuous? and self_seed != nil, do: skip_derived_works(cfg, seed)
      run_derived_works(cfg, self_derive ++ variation_seeds)
    rescue
      e ->
        IO.puts("#{tag} #{seed.task_id} (backfill) ... ERROR (#{Exception.message(e)})")
        Logger.error("backfill item crashed: " <> Exception.format(:error, e, __STACKTRACE__))
    end
  end

  # Whether a backfill seed's own harness is VACUOUS (fails the per-function
  # raise-mutant self-check). A vacuous seed blocks `wt_`/`tfim_` derivation — those
  # works promote the harness (or its blocks) as gold completions. Fixing
  # `test_harness.exs` changes the content hash, so the next run re-checks and
  # unblocks automatically.
  #
  # The verdict is deterministic for fixed content (fixed eval seed, immutable
  # tasks), and the check costs one eval subprocess per public function — it is
  # cached in `logs/seed_verdicts.jsonl` keyed by content hash so each seed pays
  # once, not on every backfill run. A crashed self-check returns `false` (derive) —
  # an infra failure must not silently freeze corpus growth; it is logged.
  # Public (@doc false) so the gate decision is unit-testable via a seeded cache.
  @doc false
  @spec vacuous_seed?(Config.t(), %{:task_id => String.t(), optional(any()) => any()}, map()) ::
          boolean()
  def vacuous_seed?(cfg, seed, files) do
    # Tier-B parents (archetype declared in manifest.exs) compile only with that
    # manifest staged alongside — the bare triplet grades every mutant
    # "inconclusive" and wrongly blocks derivation (docs/10 §5.13). The manifest
    # joins the cache key so editing it re-checks, and its absence changes nothing.
    files = put_manifest(files, Map.get(seed, :dir))

    sha =
      CycleLog.content_sha(
        files["solution.ex"] <>
          (files["test_harness.exs"] || "") <> (files["manifest.exs"] || "")
      )

    verdict =
      case CycleLog.cached_seed_verdict(cfg, seed.task_id, sha) do
        {:ok, verdict} ->
          verdict

        :miss ->
          mutant_dir = Path.join(cfg.staging_dir, seed.task_id <> "_seedmut")

          verdict =
            case Mutation.gate_base(mutant_dir, files, cfg) do
              {:survived, why} -> %{"vacuous" => true, "why" => why}
              :killed -> %{"vacuous" => false}
            end

          CycleLog.record_seed_verdict(cfg, seed.task_id, sha, verdict)
          verdict
      end

    emit_seed_verdict(seed, verdict)
    verdict["vacuous"] == true
  rescue
    e ->
      Logger.warning(
        "backfill seed #{seed.task_id}: mutation self-check failed: #{Exception.message(e)}"
      )

      false
  end

  defp put_manifest(files, nil), do: files

  defp put_manifest(files, dir) do
    path = Path.join(dir, "manifest.exs")
    if File.regular?(path), do: Map.put(files, "manifest.exs", File.read!(path)), else: files
  end

  defp emit_seed_verdict(seed, %{"vacuous" => true, "why" => why}) do
    Logger.warning(
      "backfill seed #{seed.task_id}: its own harness does NOT kill a mutant " <>
        "(#{why}) — BLOCKING wt_/tfim_ derivation until test_harness.exs is fixed " <>
        "(verdict cached in logs/seed_verdicts.jsonl; the content hash re-checks on change)"
    )
  end

  defp emit_seed_verdict(_seed, _verdict), do: :ok

  # Print + record one SKIPPED outcome per derived work type still missing for a
  # vacuous seed, so `logs/runs.jsonl` and the console carry the blockage instead of
  # silently doing nothing (work_status.exs also surfaces it corpus-wide).
  defp skip_derived_works(cfg, seed) do
    for work <- Work.derived(cfg), work.missing.(seed, cfg) > 0 do
      out =
        GenTask.Cycle.outcome(
          id: seed.task_id,
          kind: work.key,
          num: seed.num,
          status: :skipped,
          attempts: 0,
          reason: "vacuous seed harness — fix test_harness.exs (see logs/seed_verdicts.jsonl)"
        )

      record_and_print(cfg, "     ", out, nil)
    end

    :ok
  end

  # ------------------------------------------------------------------
  # Derivative drivers
  # ------------------------------------------------------------------

  defp run_variations(%Config{skip_variations: true}, _seed), do: []

  defp run_variations(cfg, base_seed) do
    outs = Variations.run(base_seed, cfg)
    Enum.each(outs, &record_and_print(cfg, "     ", &1, nil))
    outs |> Enum.filter(&(&1.status == :accepted)) |> Enum.map(& &1.seed)
  end

  defp run_fim(%Config{skip_fim: true}, _seeds), do: :ok

  defp run_fim(cfg, seeds) do
    Enum.each(seeds, fn seed ->
      seed
      |> Fim.run(cfg)
      |> Enum.each(&record_and_print(cfg, "     ", &1, nil))
    end)
  end

  # Run every registered `:derived`-stage work type (see `GenTask.Work`) on each
  # seed. Adding a new deterministic derivative requires ONLY a registry entry —
  # this driver, the backfill planner, and work_status.exs pick it up automatically.
  defp run_derived_works(cfg, seeds) do
    for work <- Work.derived(cfg), seed <- seeds do
      {mod, fun} = work.runner

      mod
      |> apply(fun, [seed, cfg])
      |> Enum.each(&record_and_print(cfg, "     ", &1, nil))
    end

    :ok
  end

  # ------------------------------------------------------------------
  # Reporting
  # ------------------------------------------------------------------

  defp record_and_print(cfg, tag, out, ms) do
    IO.puts("#{tag} #{line(out)}")

    CycleLog.record_run(cfg, %{
      id: out.id,
      kind: out.kind,
      num: out.num,
      name: out.name,
      outcome: out.status,
      attempts: out.attempts,
      compiled: out.compiled,
      tests_passed: out.tests_passed,
      tests_failed: out.tests_failed,
      tests_total: out.tests_total,
      # `mutant_failed` is now honest per shape (docs/12 §5.1 item 5): true only where a
      # raise-mutant genuinely ran and was killed. `mutation` is the precise mode.
      mutant_failed: out.mutant_failed,
      mutation: out.mutation,
      # Acceptance provenance (S12): which gates were active + the model, so a ledger row
      # proves what standard the task passed under.
      model: cfg.model,
      quality_gate: cfg.quality_gate,
      per_fn_mutation: cfg.per_fn_mutation,
      variation_blind: not cfg.skip_variation_blind,
      elapsed_s: ms && Float.round(ms / 1000, 1)
    })
  end

  defp line(out) do
    "#{out.id} (#{out.kind}) ... #{status_text(out)}"
  end

  defp status_text(%{status: :accepted} = o) do
    "ACCEPTED (#{o.tests_passed} passed, #{mutation_note(o)}, #{o.attempts} attempt(s))"
  end

  defp status_text(%{status: :rejected} = o), do: "REJECTED (#{o.reason})"
  defp status_text(%{status: :skipped} = o), do: "SKIPPED (#{o.reason})"
  defp status_text(%{status: :error} = o), do: "ERROR (#{o.reason})"

  # The blind re-screen's RED verdict (T1.1). Without this clause a quarantined
  # unit crashed record_and_print (FunctionClauseError swallowed by the item
  # rescue) — found by code reading while extending the re-screen to variations,
  # BEFORE the flag was ever flipped.
  defp status_text(%{status: :quarantined} = o), do: "QUARANTINED (#{o.reason})"

  # Honest console note for the accepted mutation mode (docs/12 §5.1 item 5): a wt_ mint
  # inherits coverage and a tfim-bundle passes only a static check — neither runs a
  # mutant, so "mutant survived?" (the old `mutant_failed == false` text) was misleading.
  defp mutation_note(%{mutation: "inherited"}), do: "inherited coverage"
  defp mutation_note(%{mutation: "static_only"}), do: "static assertion check"
  defp mutation_note(%{mutation: mode}) when is_binary(mode), do: "mutant killed (#{mode})"
  defp mutation_note(%{mutant_failed: true}), do: "mutant killed"
  defp mutation_note(_), do: "no mutant ran"

  defp print_header(cfg, plan) do
    mode = if cfg.dry_run, do: " [DRY-RUN — no promotion / tasks.md edits]", else: ""

    IO.puts("""
    =============================================
      GenTask — task generation loop#{mode}
      model=#{cfg.model}  max_retries=#{cfg.max_retries}  max_turns=#{cfg.max_turns}  fim_max=#{cfg.fim_max_per_task}  tfim_max=#{cfg.tfim_max_per_task}
      1. backfill seeds: #{backfill_line(plan.backfill, cfg)}
      2. new bases:      #{bases_line(plan.bases, cfg)}
    =============================================
    """)
  end

  # "1 → next: 135_001_data_quality_scorer_01" — say WHICH ideas are queued and why
  # the list starts where it does (a base is pending iff its idea is in tasks.md and
  # tasks/<nnn>_001_* does not exist; already-built and external-catalog ideas are
  # not pending).
  defp bases_line(_ideas, %Config{only: :backfill}), do: "skipped (GEN_ONLY=backfill)"

  defp bases_line([], _cfg), do: "0 (every tasks.md idea already has a tasks/ dir)"

  defp bases_line(ideas, _cfg) do
    preview = ideas |> Enum.take(3) |> Enum.map_join(", ", & &1.task_id)
    more = if length(ideas) > 3, do: ", …", else: ""
    "#{length(ideas)} → next: #{preview}#{more}"
  end

  defp backfill_line(_seeds, %Config{skip_backfill: true}),
    do: "skipped (GEN_SKIP_BACKFILL=1)"

  defp backfill_line(_seeds, %Config{only: :bases}),
    do: "skipped (GEN_ONLY=bases)"

  defp backfill_line([], _cfg), do: "0 (no existing task needs variations/fim/wtest/tfim top-up)"

  defp backfill_line(seeds, _cfg) do
    preview = seeds |> Enum.take(3) |> Enum.map_join(", ", & &1.task_id)
    more = if length(seeds) > 3, do: ", …", else: ""
    "#{length(seeds)} needing top-up → next: #{preview}#{more}"
  end

  # ------------------------------------------------------------------
  # helpers
  # ------------------------------------------------------------------

  defp errored?(%Config{logs_dir: logs_dir}, id),
    do: File.exists?(Path.join([logs_dir, "errors", "#{id}.log"]))

  # The triplet plus the tier manifest when the dir has one: tier-B parents
  # compile only with manifest.exs staged alongside (docs/10 §5.13) — the bare
  # triplet made every derivative eval of 016_001 misdetect tier A and fail on
  # missing Phoenix kit modules (found live 2026-07-12, bundle-fim attempt 0).
  defp read_triplet(dir) do
    files =
      for f <- ["prompt.md", "test_harness.exs", "solution.ex"],
          path = Path.join(dir, f),
          File.regular?(path),
          into: %{},
          do: {f, File.read!(path)}

    if map_size(files) == 3, do: put_manifest(files, dir), else: nil
  end

  defp slug_of(task_id) do
    task_id
    |> String.split("_")
    |> Enum.drop(2)
    |> Enum.drop(-1)
    |> Enum.join("_")
  end

  defp humanize(slug), do: slug |> String.replace("_", " ")

  defp timed(fun) do
    t0 = System.monotonic_time(:millisecond)
    result = fun.()
    {System.monotonic_time(:millisecond) - t0, result}
  end

  defp pad(i, n), do: String.pad_leading(to_string(i), String.length(to_string(n)))
end
