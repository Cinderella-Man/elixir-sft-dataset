# Live status of EVERY registered work type across the corpus — the answer to
# "what still needs to happen on which task sets?". Read-only, recomputed from
# disk each run, so call it as often as you like (before/after generation runs).
#
#   mix run scripts/work_status.exs             # the work-type × corpus matrix
#   mix run scripts/work_status.exs --pending   # + per-seed pending detail
#   mix run scripts/work_status.exs --counts    # one compact line (progress tracking)
#
# The rows come from the `GenTask.Work` registry — adding a new work type there
# makes it appear here (and in the generate.exs backfill executor) automatically.

alias GenTask.{Catalog, Config, Work}

cfg = Config.new([])
seeds = Catalog.all_seeds(cfg)
summary = Work.summary(cfg)
bases_todo = Catalog.todo_bases(Catalog.ideas(cfg), cfg)

pad = fn s, n -> String.pad_trailing(to_string(s), n) end
padl = fn s, n -> String.pad_leading(to_string(s), n) end

cond do
  "--counts" in System.argv() ->
    line =
      Enum.map_join(summary, " ", fn r ->
        "#{r.key}=#{r.pending_seeds}/#{r.applicable}(+#{r.missing_units})"
      end)

    IO.puts("bases_todo=#{length(bases_todo)} seeds=#{length(seeds)} #{line}")

  true ->
    IO.puts("== Work status (#{length(seeds)} _01 seeds on disk; recomputed live) ==\n")

    IO.puts(
      pad.("work type", 13) <>
        pad.("stage", 10) <>
        pad.("llm", 5) <>
        padl.("applicable", 11) <>
        padl.("complete", 10) <>
        padl.("pending", 9) <>
        padl.("missing units", 15) <> "  note"
    )

    for r <- summary do
      note =
        cond do
          r.skipped? -> "SKIPPED by GEN_SKIP_* flag"
          r.pending_seeds == 0 -> "✓ nothing to do"
          true -> ""
        end

      IO.puts(
        pad.(r.key, 13) <>
          pad.(r.stage, 10) <>
          pad.(if(r.llm?, do: "yes", else: "no"), 5) <>
          padl.(r.applicable, 11) <>
          padl.(r.complete, 10) <>
          padl.(r.pending_seeds, 9) <>
          padl.(r.missing_units, 15) <> "  #{note}"
      )
    end

    IO.puts(
      "\nnew bases pending (tasks.md idea, no tasks/ dir yet): #{length(bases_todo)}" <>
        if(bases_todo != [],
          do: " — next: " <> Enum.map_join(Enum.take(bases_todo, 3), ", ", & &1.task_id),
          else: ""
        )
    )

    IO.puts("caps: fim_max=#{cfg.fim_max_per_task} tfim_max=#{cfg.tfim_max_per_task}")

    if "--pending" in System.argv() do
      IO.puts("\n-- per-seed pending work --")

      for seed <- seeds, pending = Work.pending(seed, cfg), pending != %{} do
        detail = Enum.map_join(pending, ", ", fn {k, n} -> "#{k}: #{n}" end)
        IO.puts("  #{seed.task_id}  →  #{detail}")
      end
    end

    IO.puts("""

    To perform whatever is missing (idempotent — safe to re-run any time):
      mix run scripts/generate.exs                      # everything (bases + backfill)
      GEN_ONLY=backfill mix run scripts/generate.exs    # only top-up existing seeds
    """)
end
