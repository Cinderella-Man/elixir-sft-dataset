# Prototype §4.3: mutant-repair task minting — zero LLM.
# Run: mix run scratchpad/proto_mutant_repair.exs (from repo root, path adjusted below)
#
# 1. Pick a solved task, mutate ONE public function with GenTask.Mutation.mutate_fn
# 2. Grade the mutant with the real evaluator (subprocess, like the loop does)
# 3. Harvest the failure JSON -> assemble a repair-task prompt.md
# 4. Sanity: the original solution must grade green in the same dir

repo = File.cwd!()
scratch = Path.join(System.tmp_dir!(), "mutant_repair_proto")
File.rm_rf!(scratch)

task_dir = Path.join(repo, "tasks/002_001_circuit_breaker_01")
src = File.read!(Path.join(task_dir, "solution.ex"))

fns = GenTask.Mutation.public_functions(src)
IO.puts("public functions: #{inspect(fns)}")

# pick a mid-module target (not start_link, to keep the break interesting)
{name, arity} = Enum.find(fns, fn {n, _} -> n not in [:start_link, :child_spec] end)
IO.puts("mutating: #{name}/#{arity}")

mutant_src = GenTask.Mutation.mutate_fn(src, name, arity, :def)

proto_dir = Path.join(scratch, "repair_002_001_circuit_breaker")
File.mkdir_p!(proto_dir)
File.cp!(Path.join(task_dir, "test_harness.exs"), Path.join(proto_dir, "test_harness.exs"))
File.write!(Path.join(proto_dir, "solution.ex"), mutant_src)

grade = fn dir, sol ->
  {out, status} =
    System.cmd("elixir", [Path.join(repo, "scripts/eval_task.exs"), dir, sol],
      cd: repo,
      stderr_to_stdout: true
    )

  json = out |> String.split("\n", trim: true) |> List.last()

  case Jason.decode(json) do
    {:ok, m} -> m
    _ -> %{"error" => "no JSON (exit #{status})", "raw" => String.slice(out, 0, 500)}
  end
end

IO.puts("\n-- grading MUTANT --")
mres = grade.(proto_dir, "solution.ex")

IO.puts(
  "compiled=#{mres["compiled"]} passed=#{mres["tests_passed"]}/#{mres["tests_total"]} " <>
    "failed=#{mres["tests_failed"]} score=#{mres["score"] && mres["score"]["overall"]}"
)

failures = mres["test_failures"] || []
IO.puts("captured failures: #{length(failures)}")

if failures != [] do
  f = hd(failures)
  IO.puts("sample failure keys: #{inspect(Map.keys(f))}")
  IO.puts(String.slice(inspect(f), 0, 400))
end

# 3. assemble the repair prompt exactly as a minted task would carry it
orig_prompt = File.read!(Path.join(task_dir, "prompt.md"))

failure_report =
  failures
  |> Enum.take(5)
  |> Enum.map_join("\n\n", fn f ->
    "### #{f["test"] || f["name"]}\n```\n#{String.slice(f["message"] || "", 0, 800)}\n```"
  end)

repair_prompt = """
My CircuitBreaker module is failing some tests and I can't figure out why.

Here's what I was building:

#{orig_prompt |> String.split("\n") |> Enum.take(6) |> Enum.join("\n")}
...

Here's my current code:

```elixir
#{mutant_src}
```

And these tests are failing:

#{failure_report}

Can you find the bug and fix the module?
"""

File.write!(Path.join(proto_dir, "prompt.md"), repair_prompt)
IO.puts("\nrepair prompt assembled: #{byte_size(repair_prompt)} bytes -> #{proto_dir}/prompt.md")

# 4. gold check: original solution green in this dir
File.write!(Path.join(proto_dir, "solution_gold.ex"), src)
IO.puts("\n-- grading GOLD --")
gres = grade.(proto_dir, "solution_gold.ex")

IO.puts(
  "compiled=#{gres["compiled"]} passed=#{gres["tests_passed"]}/#{gres["tests_total"]} " <>
    "failed=#{gres["tests_failed"]} score=#{gres["score"] && gres["score"]["overall"]}"
)

ok? = mres["tests_failed"] > 0 and gres["tests_failed"] == 0 and gres["tests_passed"] > 0
IO.puts("\nPROTOTYPE #{if ok?, do: "VIABLE", else: "FAILED"}")
