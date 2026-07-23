defmodule GenTask.AdaptTest do
  use ExUnit.Case, async: true

  alias GenTask.{Adapt, Catalog, Config, CycleLog}

  # A sandbox with its own tasks_dir AND logs_dir, so no test can touch the real
  # corpus or the real RED-gate ledger.
  defp sandbox do
    root = Path.join(System.tmp_dir!(), "adapt_test_#{System.unique_integer([:positive])}")
    tasks = Path.join(root, "tasks")
    logs = Path.join(root, "logs")
    File.mkdir_p!(tasks)
    File.mkdir_p!(logs)
    on_exit(fn -> File.rm_rf!(root) end)
    %Config{tasks_dir: tasks, logs_dir: logs}
  end

  defp write_dir(cfg, id, files) do
    dir = Path.join(cfg.tasks_dir, id)
    File.mkdir_p!(dir)
    for {name, body} <- files, do: File.write!(Path.join(dir, name), body)
    dir
  end

  defp triplet(tag) do
    %{
      "prompt.md" => "# Task #{tag}\n\nBuild the #{tag} thing.\n",
      "solution.ex" => "defmodule S#{tag} do\n  def go(x), do: x\nend\n",
      "test_harness.exs" =>
        "defmodule S#{tag}Test do\n  use ExUnit.Case\n\n  test \"t\" do\n    assert true\n  end\nend\n"
    }
  end

  defp seed_for(cfg, task_id) do
    [s] = Catalog.all_seeds(cfg) |> Enum.filter(&(&1.task_id == task_id))
    s
  end

  defp ledger_row(cfg, base_dir, var_dir, verdict) do
    row = %{
      variation: Path.basename(var_dir),
      base: Path.basename(base_dir),
      base_solution_sha: CycleLog.content_sha(File.read!(Path.join(base_dir, "solution.ex"))),
      variation_harness_sha:
        CycleLog.content_sha(File.read!(Path.join(var_dir, "test_harness.exs"))),
      verdict: verdict,
      ts: "2026-01-01T00:00:00Z"
    }

    File.write!(
      Path.join(cfg.logs_dir, "adapt_redgate.jsonl"),
      Jason.encode!(row) <> "\n",
      [:append]
    )
  end

  describe "prompt_md/3" do
    test "embeds the base gold in a fence and the variation spec verbatim" do
      prompt =
        Adapt.prompt_md("defmodule A do\nend\n", "# New spec\n\nDo B instead.\n", "adapt_x")

      assert prompt =~ "```elixir\ndefmodule A do\nend\n```"
      assert prompt =~ "# New spec\n\nDo B instead."
      assert prompt =~ "## New specification"

      # Deterministic: same inputs, same bytes (the resync gate depends on this).
      assert prompt ==
               Adapt.prompt_md(
                 "defmodule A do\nend\n",
                 "# New spec\n\nDo B instead.\n",
                 "adapt_x"
               )
    end
  end

  describe "adapt_id/1" do
    test "drops the trailing _01 like wt_" do
      assert Adapt.adapt_id("022_002_role_scoped_01") == "adapt_022_002_role_scoped"
    end
  end

  describe "missing_units/2" do
    test "a base seed owes nothing" do
      cfg = sandbox()
      write_dir(cfg, "001_001_base_01", triplet("Base"))
      write_dir(cfg, "001_002_var_01", triplet("Var"))

      assert Adapt.missing_units(seed_for(cfg, "001_001_base_01"), cfg) == 0
    end

    test "a variation with no base sibling owes nothing" do
      cfg = sandbox()
      write_dir(cfg, "001_002_var_01", triplet("Var"))

      assert Adapt.missing_units(seed_for(cfg, "001_002_var_01"), cfg) == 0
    end

    test "a variation with a base sibling and no adapt_ dir owes one unit" do
      cfg = sandbox()
      write_dir(cfg, "001_001_base_01", triplet("Base"))
      write_dir(cfg, "001_002_var_01", triplet("Var"))

      assert Adapt.missing_units(seed_for(cfg, "001_002_var_01"), cfg) == 1
    end

    test "an existing adapt_ dir satisfies the seed" do
      cfg = sandbox()
      write_dir(cfg, "001_001_base_01", triplet("Base"))
      write_dir(cfg, "001_002_var_01", triplet("Var"))
      write_dir(cfg, "adapt_001_002_var", %{"prompt.md" => "x"})

      assert Adapt.missing_units(seed_for(cfg, "001_002_var_01"), cfg) == 0
    end

    test "a green_not_mintable verdict for the CURRENT shas suppresses the unit" do
      cfg = sandbox()
      base = write_dir(cfg, "001_001_base_01", triplet("Base"))
      var = write_dir(cfg, "001_002_var_01", triplet("Var"))
      ledger_row(cfg, base, var, "green_not_mintable")

      assert Adapt.missing_units(seed_for(cfg, "001_002_var_01"), cfg) == 0
    end

    test "a harness-less variation owes nothing (no gate to inherit)" do
      cfg = sandbox()
      write_dir(cfg, "001_001_base_01", triplet("Base"))
      files = Map.delete(triplet("Var"), "test_harness.exs")
      write_dir(cfg, "001_002_var_01", files)

      assert Adapt.missing_units(seed_for(cfg, "001_002_var_01"), cfg) == 0
    end

    test "a green verdict measured on OTHER content does not suppress the unit" do
      cfg = sandbox()
      base = write_dir(cfg, "001_001_base_01", triplet("Base"))
      var = write_dir(cfg, "001_002_var_01", triplet("Var"))
      ledger_row(cfg, base, var, "green_not_mintable")
      # The base gold is edited after the measurement: the row is now stale
      # (CONTEXT.md rule 7 — a repaired gold auto-invalidates old verdicts).
      File.write!(Path.join(base, "solution.ex"), "defmodule SBase2 do\nend\n")

      assert Adapt.missing_units(seed_for(cfg, "001_002_var_01"), cfg) == 1
    end
  end

  describe "red_gate/3" do
    test "reuses a ledger verdict keyed to the current shas without re-grading" do
      cfg = sandbox()
      base = write_dir(cfg, "001_001_base_01", triplet("Base"))
      var = write_dir(cfg, "001_002_var_01", triplet("Var"))
      # If the cache were ignored, grading this fixture from the test process
      # would return a different verdict shape (:red_crash at best) — :red_tests
      # can only come from the planted row.
      ledger_row(cfg, base, var, "red_tests")

      assert Adapt.red_gate(cfg, base, var) == :red_tests
    end
  end

  describe "run/2 cheap guards" do
    test "skip flag, base seeds, and existing dirs all no-op" do
      cfg = sandbox()

      seed = %{
        num: 1,
        slug: "var",
        b: 2,
        task_id: "001_002_var_01",
        files: triplet("Var")
      }

      assert Adapt.run(seed, %Config{cfg | skip_adapt: true}) == []
      assert Adapt.run(%{seed | b: 1}, cfg) == []

      write_dir(cfg, "adapt_001_002_var", %{"prompt.md" => "x"})
      assert Adapt.run(seed, cfg) == []
    end
  end
end
