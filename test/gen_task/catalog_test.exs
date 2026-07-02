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
      dir = tmp_dir()

      # idea 10: bare base -> needs variations AND fim
      File.mkdir_p!(Path.join(dir, "010_001_gamma_01"))

      # idea 11: base with only 1 of 3 variations and 1 of 3 fim -> STILL needs both
      # (top-up semantics: a partial batch is revisited, not treated as complete).
      File.mkdir_p!(Path.join(dir, "011_001_delta_01"))
      File.mkdir_p!(Path.join(dir, "011_001_delta_02"))
      File.mkdir_p!(Path.join(dir, "011_002_epsilon_01"))

      # idea 12: fully derived -> 3 variations, each _01 with all 3 fim subtasks.
      for d <- [
            "012_001_zeta_01",
            "012_001_zeta_02",
            "012_001_zeta_03",
            "012_001_zeta_04",
            "012_002_a_01",
            "012_002_a_02",
            "012_002_a_03",
            "012_002_a_04",
            "012_003_b_01",
            "012_003_b_02",
            "012_003_b_03",
            "012_003_b_04",
            "012_004_c_01",
            "012_004_c_02",
            "012_004_c_03",
            "012_004_c_04"
          ],
          do: File.mkdir_p!(Path.join(dir, d))

      cfg = %Config{tasks_dir: dir}
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
