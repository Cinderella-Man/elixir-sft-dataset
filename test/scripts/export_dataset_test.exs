System.put_env("SCRIPTS_NO_AUTORUN", "1")
Code.require_file("scripts/export_dataset.exs")

defmodule Scripts.ExportDatasetTest do
  use ExUnit.Case, async: true

  describe "family_of/1 (the leakage unit, docs/16 §1)" do
    test "every shape prefix collapses to the base idea `a`" do
      assert ExportDataset.family_of("016_003_x_01") == "016"
      assert ExportDataset.family_of("wt_016_001_x") == "016"
      assert ExportDataset.family_of("tfim_016_001_x_07") == "016"
      assert ExportDataset.family_of("bugfix_016_002_x_01") == "016"
      assert ExportDataset.family_of("adapt_016_002_x") == "016"
      assert ExportDataset.family_of("repair_016_001_x") == "016"
    end

    test "a name outside the convention raises instead of guessing" do
      assert_raise RuntimeError, ~r/naming convention/, fn ->
        ExportDataset.family_of("dedoc_16_x")
      end
    end
  end

  describe "split_of/1 (deterministic, content-free, docs/16 §3)" do
    test "the four measured val families stay val; a known train family stays train" do
      # These four ARE the current val split (docs/15, 2026-07-14). If this
      # test ever fails, the split moved — which must never happen without a
      # deliberate split-v2 bump.
      for fam <- ~w(032 065 073 108), do: assert(ExportDataset.split_of(fam) == "val")
      for fam <- ~w(001 016 043 105), do: assert(ExportDataset.split_of(fam) == "train")
    end

    test "same family, same answer, every time" do
      for fam <- ~w(001 032 626),
          do: assert(ExportDataset.split_of(fam) == ExportDataset.split_of(fam))
    end
  end

  describe "the contract maps cover every shape Discovery can emit" do
    # A new shape added to Discovery without an exporter mapping must fail HERE,
    # in the suite — not at export time in CI.
    @discovery_shapes [:single, :multifile, :fim, :write_test, :test_fim, :bugfix, :adapt]

    test "gold_file_map is total over shapes" do
      for shape <- @discovery_shapes do
        assert Map.has_key?(ExportDataset.gold_file_map(), shape), "no gold rule for #{shape}"
      end
    end

    test "weights_map is total over shapes" do
      for shape <- @discovery_shapes do
        assert Map.has_key?(ExportDataset.weights_map(), shape), "no weight for #{shape}"
      end
    end

    test "write_test is the only shape whose gold is not solution.ex (the §2.1 trap)" do
      {harness_shapes, solution_shapes} =
        Enum.split_with(ExportDataset.gold_file_map(), fn {_s, f} -> f == "test_harness.exs" end)

      assert Enum.map(harness_shapes, &elem(&1, 0)) == [:write_test]
      assert Enum.all?(solution_shapes, fn {_s, f} -> f == "solution.ex" end)
    end
  end
end
