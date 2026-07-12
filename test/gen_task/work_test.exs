defmodule GenTask.WorkTest do
  use ExUnit.Case, async: true

  alias GenTask.{Catalog, Config, Work}

  defp tmp_dir do
    dir = Path.join(System.tmp_dir!(), "work_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp seed(dir, task_id, opts \\ []) do
    File.mkdir_p!(Path.join(dir, task_id))

    if opts[:postgres] do
      File.write!(Path.join([dir, task_id, "manifest.exs"]), "%{db: :postgres}\n")
    end

    cfg = %Config{tasks_dir: dir, fim_max_per_task: 3, tfim_max_per_task: 3}
    [s] = Catalog.all_seeds(cfg) |> Enum.filter(&(&1.task_id == task_id))
    {s, cfg}
  end

  # A harness with `n` carvable top-level test blocks (what missing(:test_fim)
  # counts since it began delegating to TestFim.mintable_candidates/2).
  defp write_harness(dir, task_id, n) do
    File.mkdir_p!(Path.join(dir, task_id))

    tests =
      Enum.map_join(1..n, "\n", fn i ->
        "  test \"case #{i}\" do\n    assert #{i} == #{i}\n  end\n"
      end)

    File.write!(
      Path.join([dir, task_id, "test_harness.exs"]),
      "defmodule W#{:erlang.unique_integer([:positive])}Test do\n  use ExUnit.Case\n\n#{tests}end\n"
    )
  end

  describe "registry shape" do
    test "every entry carries the full contract" do
      for w <- Work.all() do
        assert is_atom(w.key)
        assert is_binary(w.desc)
        assert is_boolean(w.llm?)
        assert w.stage in [:expand, :per_seed, :derived]
        assert is_function(w.skip?, 1)
        assert is_function(w.missing, 2)
        if w.stage == :derived, do: assert(match?({_mod, _fun}, w.runner))
      end
    end

    test "fetch!/1 raises on unknown work type" do
      assert_raise ArgumentError, fn -> Work.fetch!(:nope) end
    end

    test "derived/1 honors the GEN_SKIP_* flags" do
      keys = Work.derived(%Config{}) |> Enum.map(& &1.key)
      assert :write_test in keys and :test_fim in keys

      keys = Work.derived(%Config{skip_test_fim: true}) |> Enum.map(& &1.key)
      refute :test_fim in keys
    end
  end

  describe "missing/3 + pending/2" do
    test "a bare base needs everything" do
      dir = tmp_dir()
      write_harness(dir, "010_001_gamma_01", 3)
      {s, cfg} = seed(dir, "010_001_gamma_01")

      assert Work.missing(:variations, s, cfg) == 3
      assert Work.missing(:fim, s, cfg) == 3
      assert Work.missing(:write_test, s, cfg) == 1
      assert Work.missing(:test_fim, s, cfg) == 3

      assert Work.pending(s, cfg) == %{variations: 3, fim: 3, write_test: 1, test_fim: 3}
    end

    test "test_fim counts only carvable blocks, not empty slots" do
      dir = tmp_dir()

      # 2 carvable top-level tests, 3 slots → 2 missing (capped by carvable).
      write_harness(dir, "012_001_zeta_01", 2)
      {s, cfg} = seed(dir, "012_001_zeta_01")
      assert Work.missing(:test_fim, s, cfg) == 2

      # All tests inside describe blocks → nothing carvable → 0 missing,
      # NOT tfim_max: the minter cannot fill those slots and the backfill
      # must not stay pending forever (the 2026-07-12 phantom-326 case).
      File.write!(Path.join([dir, "013_001_eta_01", "test_harness.exs"]) |> tap(fn p -> File.mkdir_p!(Path.dirname(p)) end), """
      defmodule EtaTest do
        use ExUnit.Case

        describe "grouped" do
          test "one" do
            assert 1 == 1
          end

          test "two" do
            assert 2 == 2
          end
        end
      end
      """)

      {s2, cfg2} = seed(dir, "013_001_eta_01")
      assert Work.missing(:test_fim, s2, cfg2) == 0

      # No harness on disk at all → 0 (a broken dir must not hold the backfill open).
      {s3, cfg3} = seed(dir, "014_001_theta_01")
      assert Work.missing(:test_fim, s3, cfg3) == 0
    end

    test "top-up: partial derivatives reduce, complete ones zero out" do
      dir = tmp_dir()

      for d <- ~w(011_001_delta_01 011_001_delta_02 011_002_epsilon_01
                  wt_011_001_delta tfim_011_001_delta_02 tfim_011_001_delta_03
                  tfim_011_001_delta_04),
          do: File.mkdir_p!(Path.join(dir, d))

      {s, cfg} = seed(dir, "011_001_delta_01")

      assert Work.missing(:variations, s, cfg) == 2
      assert Work.missing(:fim, s, cfg) == 2
      assert Work.missing(:write_test, s, cfg) == 0
      assert Work.missing(:test_fim, s, cfg) == 0
    end

    test "a variation seed never needs variations" do
      dir = tmp_dir()
      File.mkdir_p!(Path.join(dir, "011_001_delta_01"))
      {s, cfg} = seed(dir, "011_002_epsilon_01")

      assert Work.missing(:variations, s, cfg) == 0
    end

    test "a gradable-skip seed needs nothing parent-harness-graded" do
      dir = tmp_dir()
      {s, cfg} = seed(dir, "017_001_search_01", postgres: true)

      assert s.skip?
      assert Work.missing(:fim, s, cfg) == 0
      assert Work.missing(:write_test, s, cfg) == 0
      assert Work.missing(:test_fim, s, cfg) == 0
      assert Work.pending(s, cfg) == %{variations: 3}
    end
  end

  describe "summary/1" do
    test "aggregates applicable/complete/pending per work type" do
      dir = tmp_dir()
      write_harness(dir, "010_001_gamma_01", 3)
      File.mkdir_p!(Path.join(dir, "wt_010_001_gamma"))
      cfg = %Config{tasks_dir: dir, fim_max_per_task: 3, tfim_max_per_task: 3}

      by_key = Map.new(Work.summary(cfg), &{&1.key, &1})

      assert by_key.write_test.applicable == 1
      assert by_key.write_test.pending_seeds == 0
      assert by_key.write_test.complete == 1
      assert by_key.test_fim.pending_seeds == 1
      assert by_key.test_fim.missing_units == 3
      assert by_key.variations.pending_seeds == 1
    end
  end
end
