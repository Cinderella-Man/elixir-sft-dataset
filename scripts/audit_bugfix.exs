# audit_bugfix.exs — six-property audit of ACCEPTED bugfix units (docs/13 §1.1).
#
# For each dir (args = dir names under tasks/, or full paths): rebuild both
# sides live through the real evaluator and verify everything the shape
# promises — the buggy module reproducibly FAILS the parent harness, the
# failing tests match the report embedded in the prompt, the gold passes and
# is byte-identical to the parent reference, the bug is EXACTLY one line, and
# the task spec is included. Zero LLM. Born from Kamil's 2026-07-12 accept
# spot check, which caught AST-reprinted buggy modules (0/8) that every
# behavioral gate had passed.
#
#   mix run scripts/audit_bugfix.exs bugfix_001_001_rate_limiter_01 ...
#   mix run scripts/audit_bugfix.exs $(ls -d tasks/bugfix_* | shuf -n 10)

alias GenTask.{Config, Evaluator}

sample_ids = System.argv()

cfg = Config.new([])

results =
  for id <- sample_ids do
    dir = if File.dir?(id), do: id, else: Path.join("tasks", id)
    prompt = File.read!(Path.join(dir, "prompt.md"))
    gold = File.read!(Path.join(dir, "solution.ex"))

    parent = EvalTask.Runner.bugfix_parent_dir(dir)
    parent_sol = File.read!(Path.join(parent, "solution.ex"))
    harness = File.read!(Path.join(parent, "test_harness.exs"))

    [_, buggy] = Regex.run(~r/## The buggy module\n\n```elixir\n(.*?)\n```/s, prompt)
    [_, report] = Regex.run(~r/## Failing test report\n\n```\n(.*?)\n```/s, prompt)

    stage =
      Evaluator.stage!(Path.join(cfg.staging_dir, "accept_audit"), %{
        "prompt.md" => "audit",
        "solution.ex" => parent_sol,
        "test_harness.exs" => harness
      })

    buggy_path = Path.join(cfg.staging_dir, "accept_audit_buggy.ex")
    File.write!(buggy_path, buggy <> "\n")

    # A buggy module may hang or crash outright against a harness it was not
    # minted for (e.g. after a parent redesign) — that is a verdict, not a
    # reason to abort the sweep. Fold any non-ok grade into an empty result
    # so every property below reads as failed for that side.
    grade_or_empty = fn args ->
      case apply(Evaluator, :grade, args) do
        {:ok, g} -> g
        err -> %{"grade_error" => inspect(err)}
      end
    end

    bad = grade_or_empty.([stage, cfg, buggy_path])
    good = grade_or_empty.([stage, cfg])

    reported_tests =
      ~r/^  \* (test .+)$/m
      |> Regex.scan(report, capture: :all_but_first)
      |> Enum.map(fn [t] -> String.trim(t) end)
      |> Enum.sort()

    actual_failed =
      (bad["test_failures"] || [])
      |> Enum.map(& &1["test"])
      |> Enum.sort()

    diff_lines =
      Enum.zip(String.split(buggy, "\n"), String.split(String.trim_trailing(parent_sol), "\n"))
      |> Enum.count(fn {a, b} -> a != b end)

    checks = %{
      buggy_fails: (bad["tests_failed"] || 0) > 0,
      report_matches:
        reported_tests != [] and
          Enum.all?(reported_tests, fn t -> Enum.any?(actual_failed, &String.contains?(t, &1)) end),
      gold_passes: (good["tests_failed"] || 0) == 0 and (good["tests_passed"] || 0) > 0,
      gold_is_parent: gold == parent_sol,
      one_line_bug: diff_lines == 1,
      # Content, not heading: the register rotation (docs/20) varies the spec
      # section's heading per unit, and what this property MEANS is that the
      # parent's task statement rides in the prompt verbatim.
      spec_included: String.contains?(prompt, String.trim(File.read!(Path.join(parent, "prompt.md"))))
    }

    fails = for {k, v} <- checks, not v, do: k

    IO.puts(
      "#{if fails == [], do: "PASS", else: "FAIL #{inspect(fails)}"}  #{id}  " <>
        "(bug fails #{bad["tests_failed"]}/#{bad["tests_total"]}, diff=#{diff_lines} line)"
    )

    {id, fails}
  end

bad = Enum.filter(results, fn {_, f} -> f != [] end)

IO.puts(
  "\n#{length(results) - length(bad)}/#{length(results)} accepted units verified on every property"
)

# Gate semantics for CI (STATUS T3.2): any failed property is a real defect in
# shipped data — fail loudly, never exit 0 with a FAIL in the text.
if bad != [], do: System.halt(1)
