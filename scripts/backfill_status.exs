# Read-only, live status of the backfill work-list, recomputed from disk each run.
# Usage:
#   mix run scripts/backfill_status.exs            # human summary + per-category lists
#   mix run scripts/backfill_status.exs --counts   # one compact line (for progress tracking)
#   mix run scripts/backfill_status.exs --md        # write/refresh BACKFILL_PROGRESS.md baseline table
alias GenTask.{Catalog, Config}

cfg = Config.new([])
seeds = GenTask.CLI.plan(cfg).backfill

vars = Enum.filter(seeds, & &1.needs_variations?)
fim = Enum.filter(seeds, & &1.needs_fim?)
wt = Enum.filter(seeds, & &1.needs_write_test?)
tfim = Enum.filter(seeds, & &1.needs_test_fim?)

# Corpus-wide tallies (independent of "needs something").
all_01 = Path.wildcard("#{cfg.tasks_dir}/*_01") |> Enum.filter(&File.dir?/1)
wt_dirs = Path.wildcard("#{cfg.tasks_dir}/wt_*") |> Enum.filter(&File.dir?/1)
tfim_dirs = Path.wildcard("#{cfg.tasks_dir}/tfim_*") |> Enum.filter(&File.dir?/1)

sfim_dirs =
  Path.wildcard("#{cfg.tasks_dir}/*")
  |> Enum.filter(fn d ->
    b = Path.basename(d)

    File.dir?(d) and Regex.match?(~r/^\d/, b) and
      (case Integer.parse(List.last(String.split(b, "_"))) do
         {n, ""} -> n >= 2
         _ -> false
       end)
  end)

counts =
  "REMAINING seeds=#{length(seeds)} vars=#{length(vars)} fim=#{length(fim)} " <>
    "wt=#{length(wt)} tfim=#{length(tfim)} | CORPUS _01=#{length(all_01)} " <>
    "sfim=#{length(sfim_dirs)} wt_=#{length(wt_dirs)} tfim_=#{length(tfim_dirs)}"

cond do
  "--counts" in System.argv() ->
    IO.puts(counts)

  true ->
    IO.puts("== Backfill live status ==")
    IO.puts(counts)
    IO.puts("\n-- needs VARIATIONS (#{length(vars)}) --")
    Enum.each(vars, &IO.puts("  #{&1.task_id}"))

    IO.puts("\n-- needs FIM top-up (#{length(fim)}) --")
    Enum.each(fim, fn s ->
      [a, b | _] = String.split(s.task_id, "_")
      IO.puts("  #{s.task_id}  (#{Catalog.count_fim(cfg.tasks_dir, a, b)}/#{cfg.fim_max_per_task})")
    end)

    IO.puts("\n-- needs WRITE_TEST (#{length(wt)}) --")
    Enum.each(wt, &IO.puts("  #{&1.task_id}"))

    IO.puts("\n-- needs TEST_FIM top-up (#{length(tfim)}) --")
    Enum.each(tfim, fn s ->
      [a, b | _] = String.split(s.task_id, "_")
      IO.puts("  #{s.task_id}  (#{Catalog.count_tfim(cfg.tasks_dir, a, b)}/#{cfg.tfim_max_per_task})")
    end)
end
