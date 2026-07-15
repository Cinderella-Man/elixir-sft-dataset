defmodule GenTask.SemanticFloorTest do
  use ExUnit.Case, async: true

  alias GenTask.{Config, Cycle, Evaluator}

  defp env(map), do: fn key -> map[key] end

  describe "GEN_SEMANTIC_FLOOR" do
    test "unset resolves to the 0.6 default — quality gates are ON by default (Kamil 2026-07-15)" do
      assert %Config{semantic_floor: 0.6} = Config.new([], env(%{}))
      assert %Config{semantic_floor: 0.6} = Config.new([], env(%{"GEN_SEMANTIC_FLOOR" => ""}))
    end

    test "only the explicit word off/none disables it (debugging)" do
      assert %Config{semantic_floor: nil} = Config.new([], env(%{"GEN_SEMANTIC_FLOOR" => "off"}))

      assert %Config{semantic_floor: nil} =
               Config.new([], env(%{"GEN_SEMANTIC_FLOOR" => "none"}))
    end

    test "a float in [0, 1] arms the gate" do
      assert %Config{semantic_floor: 0.5} =
               Config.new([], env(%{"GEN_SEMANTIC_FLOOR" => "0.5"}))

      assert %Config{semantic_floor: 1.0} =
               Config.new([], env(%{"GEN_SEMANTIC_FLOOR" => "1.0"}))
    end

    test "a typo stops the run instead of silently disabling a quality gate" do
      assert_raise ArgumentError, ~r/GEN_SEMANTIC_FLOOR/, fn ->
        Config.new([], env(%{"GEN_SEMANTIC_FLOOR" => "0.5x"}))
      end

      assert_raise ArgumentError, ~r/GEN_SEMANTIC_FLOOR/, fn ->
        Config.new([], env(%{"GEN_SEMANTIC_FLOOR" => "1.5"}))
      end
    end
  end

  describe "the reject plumbing" do
    test "reason_text names the rate and survivor count" do
      why = Cycle.reason_text({:semantic_floor, 0.4285, ["swap > for >=", "off-by-one in prune"]})
      assert why =~ "0.43"
      assert why =~ "2 surviving"
    end

    test "repair_report NAMES every survivor (scar 4: the fixer must know the criteria)" do
      report = Evaluator.repair_report({:semantic_floor, 0.5, ["swap > for >=", "drop clamp"]})
      assert report =~ "50%"
      assert report =~ "swap > for >="
      assert report =~ "drop clamp"
      assert report =~ "public API"
    end

    test "repair_report caps the named list at 10 and counts the rest" do
      survivors = for i <- 1..14, do: "mutant_#{i}"
      report = Evaluator.repair_report({:semantic_floor, 0.1, survivors})
      assert report =~ "mutant_10"
      refute report =~ "mutant_11"
      assert report =~ "4 more"
    end
  end
end
