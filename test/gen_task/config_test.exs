defmodule GenTask.ConfigTest do
  use ExUnit.Case, async: true

  alias GenTask.Config

  defp env(map), do: fn key -> map[key] end

  describe "GEN_ONLY" do
    test "accepts bases and topup" do
      assert %Config{only: :topup} = Config.new([], env(%{"GEN_ONLY" => "topup"}))
      assert %Config{only: :bases} = Config.new([], env(%{"GEN_ONLY" => "bases"}))
      assert %Config{only: nil} = Config.new([], env(%{}))
    end

    test "rejects unknown values instead of silently meaning bases" do
      assert_raise ArgumentError, ~r/GEN_ONLY/, fn ->
        Config.new([], env(%{"GEN_ONLY" => "fim"}))
      end
    end
  end

  describe "--force" do
    test "parsed from argv alongside the positional idea number" do
      assert %Config{force: true, only_idea: 15} = Config.new(["15", "--force"], env(%{}))
      assert %Config{force: true, only_idea: 15} = Config.new(["--force", "15"], env(%{}))
      assert %Config{force: false, only_idea: 15} = Config.new(["15"], env(%{}))
      assert %Config{force: false, only_idea: nil} = Config.new([], env(%{}))
    end

    test "--force alone parses; the wipe itself rejects the missing idea number" do
      # Config stays a pure snapshot — GenTask.Force.wipe!/2 raises on only_idea: nil.
      assert %Config{force: true, only_idea: nil} = Config.new(["--force"], env(%{}))
    end
  end

  describe "GEN_RECONCILE (default-on, opt-out)" do
    test "on by default; explicit 0/false disables" do
      assert %Config{reconcile: true} = Config.new([], env(%{}))
      assert %Config{reconcile: false} = Config.new([], env(%{"GEN_RECONCILE" => "0"}))
      assert %Config{reconcile: false} = Config.new([], env(%{"GEN_RECONCILE" => "false"}))
      assert %Config{reconcile: true} = Config.new([], env(%{"GEN_RECONCILE" => "1"}))
    end
  end

  describe "integer envs" do
    test "parse clean integers" do
      assert %Config{limit: 5} = Config.new([], env(%{"GEN_LIMIT" => "5"}))
    end

    test "reject trailing junk instead of truncating" do
      assert_raise ArgumentError, ~r/GEN_LIMIT/, fn ->
        Config.new([], env(%{"GEN_LIMIT" => "5x"}))
      end
    end
  end

  describe "GEN_EXCLUDE_SEEDS" do
    test "parses a comma-separated prefix list, tolerating spaces and empties" do
      assert %Config{exclude_seeds: []} = Config.new([], env(%{}))

      assert %Config{exclude_seeds: ["016_001", "102_001"]} =
               Config.new([], env(%{"GEN_EXCLUDE_SEEDS" => "016_001, 102_001,"}))
    end
  end
end
