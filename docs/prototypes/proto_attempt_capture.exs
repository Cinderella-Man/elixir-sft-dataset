# Integration check for attempt capture (docs/08): drive GenTask.Cycle.run through
# a green ACCEPT (full quality + per-fn mutation gates) and a broken REJECT, with
# logs_dir pointed at a tmp dir, then inspect logs/attempts/<id>/.

alias GenTask.{Config, Cycle, Mutation}

tmp = Path.join(System.tmp_dir!(), "attempt_capture_proto")
File.rm_rf!(tmp)
logs = Path.join(tmp, "logs")

cfg = %Config{logs_dir: logs, max_retries: 0}

task = "tasks/076_001_trie_01"

files =
  for f <- ~w(prompt.md solution.ex test_harness.exs), into: %{} do
    {f, File.read!(Path.join(task, f))}
  end

ctx = %{
  dir: Path.join(tmp, "stage"),
  mutant_dir: Path.join(tmp, "mutant"),
  id: "proto_076_green"
}

IO.puts("-- green cycle (accept path: grade + quality gate + per-fn mutation) --")
res = Cycle.run(files, ctx, cfg)
IO.puts("status=#{res.status} attempts=#{res.attempts}")

IO.puts("\n-- broken cycle (raise-mutant of insert/3 → tests fail → rejected_final) --")
broken = Map.put(files, "solution.ex", Mutation.mutate_fn(files["solution.ex"], :insert, 2))
res2 = Cycle.run(broken, %{ctx | id: "proto_076_broken"}, cfg)
IO.puts("status=#{res2.status} attempts=#{res2.attempts}")

IO.puts("\n-- captured tree under #{logs}/attempts --")

for id_dir <- Path.wildcard(Path.join(logs, "attempts/*")),
    att <- Path.wildcard(Path.join(id_dir, "attempt_*")) do
  meta = Jason.decode!(File.read!(Path.join(att, "meta.json")))
  grade = Jason.decode!(File.read!(Path.join(att, "grade.json")))
  captured = File.ls!(Path.join(att, "files")) |> Enum.sort() |> Enum.join(",")

  IO.puts(
    "#{Path.basename(id_dir)}/#{Path.basename(att)}: status=#{meta["status"]} " <>
      "files=[#{captured}] tests=#{grade["tests_passed"]}/#{grade["tests_total"]} " <>
      "failed=#{grade["tests_failed"]}"
  )

  if meta["repair_report"] do
    IO.puts("  repair_report: #{String.slice(meta["repair_report"], 0, 140)}...")
  end
end

# reset semantics: re-running the same id must replace, not accumulate
_ = Cycle.run(files, ctx, cfg)
n = Path.wildcard(Path.join(logs, "attempts/proto_076_green/attempt_*")) |> length()
IO.puts("\nafter re-run of same id: #{n} attempt dir(s) (expected 1 — reset works)")
