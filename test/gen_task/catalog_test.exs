defmodule GenTask.CatalogTest do
  use ExUnit.Case, async: true

  alias GenTask.Catalog
  alias GenTask.Catalog.{Idea, Seed}
  alias GenTask.Config

  @catalog """
  # Ideas

  ## Section One

  ### 1. Rate Limiter
  A token-bucket rate limiter.
  Handles bursts gracefully.

  ### Task 1 - V1 - Sliding Window Limiter
  A sliding-window variant.

  ### 2. Saga Coordinator
  Coordinates a distributed saga.

  ## Another Section

  ### 3. Money Type
  Multi-currency money.
  """

  describe "parse_string/2 grammar" do
    test "parses base ideas in file order, skipping variations and section headers" do
      ideas = Catalog.parse_string(@catalog, non_existent_tasks_dir())

      assert Enum.map(ideas, & &1.num) == [1, 2, 3]
      assert Enum.map(ideas, & &1.name) == ["Rate Limiter", "Saga Coordinator", "Money Type"]
    end

    test "a variation line terminates the base description and is not itself an idea" do
      [rate | _] = Catalog.parse_string(@catalog, non_existent_tasks_dir())

      assert rate.desc == "A token-bucket rate limiter.\nHandles bursts gracefully."
      refute rate.desc =~ "sliding-window"
    end

    test "a section header terminates the current description" do
      ideas = Catalog.parse_string(@catalog, non_existent_tasks_dir())
      money = Enum.find(ideas, &(&1.num == 3))

      assert money.desc == "Multi-currency money."
    end

    test "computes slug and task_id" do
      [rate | _] = Catalog.parse_string(@catalog, non_existent_tasks_dir())

      assert rate.slug == "rate_limiter"
      assert rate.task_id == "001_001_rate_limiter_01"
    end
  end

  describe "identity helpers" do
    test "slug/1 downcases, collapses non-alphanumerics, trims underscores" do
      assert Catalog.slug("Rate Limiter") == "rate_limiter"
      assert Catalog.slug("Multi-Currency Money!") == "multi_currency_money"
      assert Catalog.slug("  Leading/Trailing  ") == "leading_trailing"
      assert Catalog.slug("HTTP/2 Server") == "http_2_server"
    end

    test "pad3/1 zero-pads to three digits" do
      assert Catalog.pad3(1) == "001"
      assert Catalog.pad3(42) == "042"
      assert Catalog.pad3(557) == "557"
    end

    test "task_id/2 assembles the canonical base id" do
      assert Catalog.task_id(7, "saga") == "007_001_saga_01"
    end
  end

  describe "done?/2" do
    test "true only when a matching NNN_001_*_01 directory exists" do
      dir = tmp_dir()
      File.mkdir_p!(Path.join(dir, "004_001_widget_01"))

      assert Catalog.done?(4, dir)
      refute Catalog.done?(5, dir)
    end

    test "parse_string wires done? into the Idea structs" do
      dir = tmp_dir()
      File.mkdir_p!(Path.join(dir, "002_001_saga_coordinator_01"))

      ideas = Catalog.parse_string(@catalog, dir)

      assert %Idea{num: 2, done?: true} = Enum.find(ideas, &(&1.num == 2))
      assert %Idea{num: 1, done?: false} = Enum.find(ideas, &(&1.num == 1))
    end
  end

  describe "todo_bases/2 enumeration" do
    setup do
      ideas = [
        %Idea{num: 1, done?: true},
        %Idea{num: 2, done?: false},
        %Idea{num: 3, done?: false},
        %Idea{num: 5, done?: false}
      ]

      {:ok, ideas: ideas}
    end

    test "returns not-done ideas in order", %{ideas: ideas} do
      assert Catalog.todo_bases(ideas, %Config{}) |> Enum.map(& &1.num) == [2, 3, 5]
    end

    test "honours :from / :to scope", %{ideas: ideas} do
      cfg = %Config{from: 3, to: 5}
      assert Catalog.todo_bases(ideas, cfg) |> Enum.map(& &1.num) == [3, 5]
    end

    test "honours :only_idea", %{ideas: ideas} do
      cfg = %Config{only_idea: 3}
      assert Catalog.todo_bases(ideas, cfg) |> Enum.map(& &1.num) == [3]
    end

    test "honours :limit after filtering", %{ideas: ideas} do
      cfg = %Config{limit: 2}
      assert Catalog.todo_bases(ideas, cfg) |> Enum.map(& &1.num) == [2, 3]
    end
  end

  describe "backfill_seeds/1 enumeration" do
    test "flags partially-derived tasks for top-up and excludes fully-complete ones" do
      # The fixture below is "complete" at 3 fim + 3 tfim per _01 — pin those caps
      # (the default tfim cap is now 10; completeness is relative to the cap).
      dir = tmp_dir()

      # idea 10: bare base -> needs variations AND fim (missing(:fim) now counts
      # viable targets, so the parent needs a solution with stub-able functions)
      write_fim_solution(dir, "010_001_gamma_01", 3)

      # idea 11: base with only 1 of 3 variations and 1 of 3 fim -> STILL needs both
      # (top-up semantics: a partial batch is revisited, not treated as complete).
      write_fim_solution(dir, "011_001_delta_01", 3)
      File.mkdir_p!(Path.join(dir, "011_001_delta_02"))
      write_fim_solution(dir, "011_002_epsilon_01", 3)

      # idea 12: fully derived -> 3 variations, each _01 with all 3 fim subtasks, one
      # wtest (wt_...) and all 3 tfim subtasks (tfim_..._02/03/04).
      for d <- [
            "012_001_zeta_01",
            "012_001_zeta_02",
            "012_001_zeta_03",
            "012_001_zeta_04",
            "wt_012_001_zeta",
            "tfim_012_001_zeta_02",
            "tfim_012_001_zeta_03",
            "tfim_012_001_zeta_04",
            "012_002_a_01",
            "012_002_a_02",
            "012_002_a_03",
            "012_002_a_04",
            "wt_012_002_a",
            "tfim_012_002_a_02",
            "tfim_012_002_a_03",
            "tfim_012_002_a_04",
            "012_003_b_01",
            "012_003_b_02",
            "012_003_b_03",
            "012_003_b_04",
            "wt_012_003_b",
            "tfim_012_003_b_02",
            "tfim_012_003_b_03",
            "tfim_012_003_b_04",
            "012_004_c_01",
            "012_004_c_02",
            "012_004_c_03",
            "012_004_c_04",
            "wt_012_004_c",
            "tfim_012_004_c_02",
            "tfim_012_004_c_03",
            "tfim_012_004_c_04"
          ],
          do: File.mkdir_p!(Path.join(dir, d))

      cfg = %Config{tasks_dir: dir, fim_max_per_task: 3, tfim_max_per_task: 3}
      seeds = Catalog.backfill_seeds(cfg)

      by_id = Map.new(seeds, &{&1.task_id, &1})

      assert %Seed{num: 10, base?: true, needs_variations?: true, needs_fim?: true} =
               by_id["010_001_gamma_01"]

      # delta base has only 1/3 variations and 1/3 fim -> top-up both
      assert %Seed{num: 11, base?: true, needs_variations?: true, needs_fim?: true} =
               by_id["011_001_delta_01"]

      # epsilon variation still needs fim
      assert %Seed{num: 11, base?: false, needs_variations?: false, needs_fim?: true} =
               by_id["011_002_epsilon_01"]

      # idea 12 is fully derived -> no seeds at all
      refute Enum.any?(seeds, &(&1.num == 12))

      assert MapSet.new(Map.keys(by_id)) ==
               MapSet.new(["010_001_gamma_01", "011_001_delta_01", "011_002_epsilon_01"])
    end

    test "respects idea-number scope" do
      dir = tmp_dir()
      File.mkdir_p!(Path.join(dir, "010_001_gamma_01"))
      File.mkdir_p!(Path.join(dir, "020_001_zeta_01"))

      cfg = %Config{tasks_dir: dir, from: 15}
      assert Catalog.backfill_seeds(cfg) |> Enum.map(& &1.num) == [20]
    end

    test "GEN_EXCLUDE_SEEDS drops matching seeds from the backfill list" do
      dir = tmp_dir()
      write_fim_solution(dir, "010_001_gamma_01", 3)
      write_fim_solution(dir, "020_001_zeta_01", 3)

      cfg = %Config{tasks_dir: dir, exclude_seeds: ["010_001"]}
      assert Catalog.backfill_seeds(cfg) |> Enum.map(& &1.num) == [20]
    end

    test "excludes Postgres-tier (gradable-skip) seeds from wtest/tfim backfill" do
      dir = tmp_dir()

      # A base whose eval is `skipped` (manifest db: :postgres): variations may still
      # apply (a variation is a NEW triplet with no such manifest), but FIM, wtest and
      # tfim all grade against this parent's harness — which can only ever grade
      # `skipped` — so none can be minted green and none may be flagged for backfill
      # (Finding A: FIM would additionally burn LLM repair calls on every run).
      File.mkdir_p!(Path.join(dir, "017_001_search_01"))
      File.write!(Path.join(dir, "017_001_search_01/manifest.exs"), "%{db: :postgres}\n")

      cfg = %Config{tasks_dir: dir}
      seed = Catalog.backfill_seeds(cfg) |> Enum.find(&(&1.num == 17))

      # Still a seed (kept for variations), but fim/wtest/tfim are all suppressed.
      assert %Seed{needs_fim?: false, needs_write_test?: false, needs_test_fim?: false} = seed
      assert seed.needs_variations?
    end
  end

  describe "insert_variation/5 placement + idempotency" do
    test "inserts after the last block of the target idea, before the next header" do
      {:ok, out} =
        Catalog.insert_variation(@catalog, 1, "V2", "Leaky Bucket", "A leaky-bucket variant.")

      lines = String.split(out, "\n")
      v1_idx = Enum.find_index(lines, &(&1 =~ ~r/^### Task 1 - V1 -/))
      v2_idx = Enum.find_index(lines, &(&1 =~ ~r/^### Task 1 - V2 -/))
      idea2_idx = Enum.find_index(lines, &(&1 =~ ~r/^### 2\. /))

      assert v1_idx < v2_idx
      assert v2_idx < idea2_idx
      assert out =~ "A leaky-bucket variant."
    end

    test "is idempotent when the exact variation header already exists" do
      catalog = @catalog

      assert {:already_present, ^catalog} =
               Catalog.insert_variation(catalog, 1, "V1", "Sliding Window Limiter", "dup")
    end

    test "errors when the base idea is absent" do
      assert {:error, :base_not_found} =
               Catalog.insert_variation(@catalog, 99, "V1", "Ghost", "x")
    end

    test "a second distinct insert does not duplicate or displace the first" do
      {:ok, once} = Catalog.insert_variation(@catalog, 2, "V1", "Saga With Timeouts", "d1")
      {:ok, twice} = Catalog.insert_variation(once, 2, "V2", "Saga With Retries", "d2")

      lines = String.split(twice, "\n")
      v1 = Enum.find_index(lines, &(&1 =~ ~r/^### Task 2 - V1 -/))
      v2 = Enum.find_index(lines, &(&1 =~ ~r/^### Task 2 - V2 -/))
      idea3 = Enum.find_index(lines, &(&1 =~ ~r/^### 3\. /))

      assert v1 < v2 and v2 < idea3
      # re-inserting V1 is a no-op
      assert {:already_present, ^twice} =
               Catalog.insert_variation(twice, 2, "V1", "Saga With Timeouts", "d1")
    end
  end

  # ---------------------------------------------------------------------------

  describe "reconcile_variations!/1" do
    test "inserts missing entries per variation dir (slot→Vn), idempotently" do
      dir = tmp_dir()

      for d <- [
            "050_001_widget_maker_01",
            "050_002_fast_widget_maker_01",
            "050_003_bulk_widget_maker_01"
          ],
          do: File.mkdir_p!(Path.join(dir, d))

      File.write!(
        Path.join(dir, "050_002_fast_widget_maker_01/prompt.md"),
        "# Task\n\nBuild a fast widget maker.\n"
      )

      md = Path.join(dir, "tasks.md")
      File.write!(md, "### 50. Widget Maker\nMakes widgets.\n")
      cfg = %Config{tasks_dir: dir, tasks_md: md}

      assert Catalog.reconcile_variations!(cfg) == 2
      content = File.read!(md)
      assert content =~ "### Task 50 - V1 - Fast Widget Maker"
      assert content =~ "Build a fast widget maker."
      assert content =~ "### Task 50 - V2 - Bulk Widget Maker"

      # idempotent second run
      assert Catalog.reconcile_variations!(cfg) == 0
    end

    test "skips a variation whose base idea is absent from tasks.md" do
      dir = tmp_dir()
      File.mkdir_p!(Path.join(dir, "060_002_orphan_variation_01"))
      md = Path.join(dir, "tasks.md")
      File.write!(md, "### 1. Something Else\nUnrelated.\n")
      cfg = %Config{tasks_dir: dir, tasks_md: md}

      assert Catalog.reconcile_variations!(cfg) == 0
      refute File.read!(md) =~ "Task 60"
    end
  end

  defp write_fim_solution(dir, task_id, n) do
    File.mkdir_p!(Path.join(dir, task_id))

    fns = Enum.map_join(1..n, "\n", fn i -> "  def f#{i}(x), do: x + #{i}\n" end)

    File.write!(
      Path.join([dir, task_id, "solution.ex"]),
      "defmodule C#{:erlang.unique_integer([:positive])} do\n#{fns}end\n"
    )
  end

  defp tmp_dir do
    dir =
      Path.join(
        System.tmp_dir!(),
        "gen_catalog_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp non_existent_tasks_dir do
    Path.join(System.tmp_dir!(), "gen_catalog_absent_#{System.unique_integer([:positive])}")
  end
end
