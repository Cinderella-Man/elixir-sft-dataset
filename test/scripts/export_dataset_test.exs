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

  describe "screen_difficulty/1 (majority-of-recent tier, G9 2026-07-23)" do
    defp difficulty_from(rows) do
      dir = Path.join(System.tmp_dir!(), "exp_diff_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      path = Path.join(dir, "screen_blind.jsonl")
      File.write!(path, Enum.map_join(rows, "", &(Jason.encode!(&1) <> "\n")))
      on_exit(fn -> File.rm_rf!(dir) end)
      ExportDataset.screen_difficulty(path)
    end

    test "a single red row stays keep_class; a single green row is blind_solvable" do
      d =
        difficulty_from([
          %{task: "001_001_x_01", green: false},
          %{task: "002_001_x_01", green: true}
        ])

      assert d["001_001"].tier == "keep_class"
      assert d["002_001"].tier == "blind_solvable"
    end

    test "an old red followed by 2 fresh greens flips to blind_solvable (the probe class)" do
      d =
        difficulty_from([
          %{task: "003_001_x_01", green: false},
          %{task: "003_001_x_01", green: true},
          %{task: "003_001_x_01", green: true}
        ])

      assert d["003_001"] == %{tier: "blind_solvable", attempts: 3, greens: 2}
    end

    test "a lucky last green does NOT flip a 1-of-3 history (the old last-row bug)" do
      d =
        difficulty_from([
          %{task: "004_001_x_01", green: false},
          %{task: "004_001_x_01", green: false},
          %{task: "004_001_x_01", green: true}
        ])

      assert d["004_001"].tier == "keep_class"
    end

    test "a 2-row split reads keep_class (hard until a majority proves otherwise)" do
      d =
        difficulty_from([
          %{task: "005_001_x_01", green: false},
          %{task: "005_001_x_01", green: true}
        ])

      assert d["005_001"].tier == "keep_class"
    end

    test "only the last 3 verdicts vote; counts keep the full history" do
      rows = for g <- [true, true, false, false, false], do: %{task: "006_001_x_01", green: g}
      d = difficulty_from(rows)
      assert d["006_001"] == %{tier: "keep_class", attempts: 5, greens: 2}
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
    # in the suite — not at export time in CI. The hardcoded floor alone could
    # not catch that (the :dedoc shape shipped 2026-07-19 and the export step
    # crashed in CI while this suite stayed green), so the observed shapes of
    # the REAL corpus are unioned in: any shape that actually occurs in tasks/
    # must be mapped, whether or not someone remembered to extend this list.
    @discovery_shapes [
      :single,
      :multifile,
      :fim,
      :write_test,
      :test_fim,
      :bugfix,
      :adapt,
      :dedoc
    ]

    defp shapes_to_cover do
      observed =
        EvalTask.Discovery.all()
        |> Enum.map(& &1.shape)
        |> Enum.uniq()

      Enum.uniq(@discovery_shapes ++ observed)
    end

    test "gold_file_map is total over shapes" do
      for shape <- shapes_to_cover() do
        assert Map.has_key?(ExportDataset.gold_file_map(), shape), "no gold rule for #{shape}"
      end
    end

    test "weights_map is total over shapes" do
      for shape <- shapes_to_cover() do
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
