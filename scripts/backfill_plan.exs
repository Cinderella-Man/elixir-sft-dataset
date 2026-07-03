# Read-only enumeration of the backfill work-list. No `claude` calls.
alias GenTask.{Catalog, Config}

cfg = Config.new([])
plan = GenTask.CLI.plan(cfg)

seeds = plan.backfill

vars = Enum.filter(seeds, & &1.needs_variations?)
fim = Enum.filter(seeds, & &1.needs_fim?)
wt = Enum.filter(seeds, & &1.needs_write_test?)
tfim = Enum.filter(seeds, & &1.needs_test_fim?)

IO.puts("== Backfill plan ==")
IO.puts("total todo base ideas (no _01 yet): #{length(plan.bases)}")
IO.puts("total backfill seeds (need something): #{length(seeds)}")
IO.puts("  need variations (LLM):  #{length(vars)}")
IO.puts("  need FIM (LLM):         #{length(fim)}")
IO.puts("  need write_test (det):  #{length(wt)}")
IO.puts("  need test_fim (det):    #{length(tfim)}")
IO.puts("")
IO.puts("fim_max_per_task=#{cfg.fim_max_per_task}  tfim_max_per_task=#{cfg.tfim_max_per_task}")

IO.puts("\n-- seeds needing VARIATIONS (base b: count_variations<3) --")
Enum.each(vars, fn s -> IO.puts("  #{s.task_id}") end)

IO.puts("\n-- seeds needing FIM top-up --")
Enum.each(fim, fn s ->
  [a, b | _] = String.split(s.task_id, "_")
  n = Catalog.count_fim(cfg.tasks_dir, a, b)
  IO.puts("  #{s.task_id}  (has #{n}/#{cfg.fim_max_per_task})")
end)

IO.puts("\n-- seeds needing WRITE_TEST --")
Enum.each(wt, fn s -> IO.puts("  #{s.task_id}") end)

IO.puts("\n-- seeds needing TEST_FIM top-up --")
Enum.each(tfim, fn s ->
  [a, b | _] = String.split(s.task_id, "_")
  n = Catalog.count_tfim(cfg.tasks_dir, a, b)
  IO.puts("  #{s.task_id}  (has #{n}/#{cfg.tfim_max_per_task})")
end)
