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

  # A parent solution with `n` distinct stub-able functions (what missing(:fim)
  # counts since it began delegating to Fim.missing_units/2).
  defp write_solution(dir, task_id, n) do
    File.mkdir_p!(Path.join(dir, task_id))

    fns = Enum.map_join(1..n, "\n", fn i -> "  def f#{i}(x), do: x + #{i}\n" end)

    File.write!(
      Path.join([dir, task_id, "solution.ex"]),
      "defmodule W#{:erlang.unique_integer([:positive])} do\n#{fns}end\n"
    )
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
      write_solution(dir, "010_001_gamma_01", 3)
      {s, cfg} = seed(dir, "010_001_gamma_01")

      assert Work.missing(:variations, s, cfg) == 3
      assert Work.missing(:fim, s, cfg) == 3
      assert Work.missing(:write_test, s, cfg) == 1
      assert Work.missing(:test_fim, s, cfg) == 3

      assert Work.pending(s, cfg) == %{
               variations: 3,
               fim: 3,
               write_test: 1,
               test_fim: 3,
               bugfix: 3
             }
    end

    test "test_fim counts only carvable blocks, not empty slots" do
      dir = tmp_dir()

      # 2 carvable top-level tests, 3 slots → 2 missing (capped by carvable).
      write_harness(dir, "012_001_zeta_01", 2)
      {s, cfg} = seed(dir, "012_001_zeta_01")
      assert Work.missing(:test_fim, s, cfg) == 2

      # Describe-nested tests ARE carvable since decision 4 (2026-07-12): the
      # same harness that once produced the phantom-326 zero now counts its 2
      # nested tests. Counting stays capped by what the minter can carve — a
      # harness with NO test blocks at all still counts 0 (see below).
      File.write!(
        Path.join([dir, "013_001_eta_01", "test_harness.exs"])
        |> tap(fn p -> File.mkdir_p!(Path.dirname(p)) end),
        """
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
        """
      )

      {s2, cfg2} = seed(dir, "013_001_eta_01")
      assert Work.missing(:test_fim, s2, cfg2) == 2

      # A harness with no test blocks (setup/helpers only) → nothing carvable → 0.
      File.write!(
        Path.join([dir, "015_001_iota_01", "test_harness.exs"])
        |> tap(fn p -> File.mkdir_p!(Path.dirname(p)) end),
        """
        defmodule IotaTest do
          use ExUnit.Case

          setup do
            :ok
          end
        end
        """
      )

      {s5, cfg5} = seed(dir, "015_001_iota_01")
      assert Work.missing(:test_fim, s5, cfg5) == 0

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

      write_solution(dir, "011_001_delta_01", 3)
      {s, cfg} = seed(dir, "011_001_delta_01")

      assert Work.missing(:variations, s, cfg) == 2
      assert Work.missing(:fim, s, cfg) == 2
      assert Work.missing(:write_test, s, cfg) == 0
      assert Work.missing(:test_fim, s, cfg) == 0
    end

    test "fim counts only viable targets, not empty slots" do
      dir = tmp_dir()

      # 1-function parent, 3 slots → 1 missing (capped by the target pool),
      # NOT fim_max: the selector cannot fill those slots and the backfill
      # must not stay pending forever (the 2026-07-12 stuck-13 case).
      write_solution(dir, "015_001_iota_01", 1)
      {s, cfg} = seed(dir, "015_001_iota_01")
      assert Work.missing(:fim, s, cfg) == 1

      # The one target is already covered by an existing _02 child → 0.
      write_solution(dir, "016_001_kappa_01", 1)
      File.mkdir_p!(Path.join(dir, "016_001_kappa_02"))

      File.write!(
        Path.join([dir, "016_001_kappa_02", "solution.ex"]),
        "  def f1(x), do: x + 1\n"
      )

      {s2, cfg2} = seed(dir, "016_001_kappa_01")
      assert Work.missing(:fim, s2, cfg2) == 0

      # A bundle parent is pool-capped through the marker-stripped view (the
      # 2026-07-12 bundle-fim fix made bundles ordinary fim work): 2 functions
      # across 2 files, 3 slots → 2 missing.
      File.mkdir_p!(Path.join(dir, "018_001_lambda_01"))

      File.write!(
        Path.join([dir, "018_001_lambda_01", "solution.ex"]),
        "<file path=\"lib/a.ex\">\ndefmodule A do\n  def go(x), do: x\nend\n</file>\n\n" <>
          "<file path=\"lib/b.ex\">\ndefmodule B do\n  def stop(x), do: x\nend\n</file>\n"
      )

      {s3, cfg3} = seed(dir, "018_001_lambda_01")
      assert Work.missing(:fim, s3, cfg3) == 2

      # No solution.ex on disk → 0 (a broken dir must not hold the backfill open).
      {s4, cfg4} = seed(dir, "019_001_mu_01")
      assert Work.missing(:fim, s4, cfg4) == 0
    end

    test "bugfix counts only diverse mintable mutants, zero for bundles" do
      dir = tmp_dir()

      # 3 functions with mutable literals/comparisons -> a non-empty diverse pool,
      # capped at the 3-slot maximum.
      write_solution(dir, "020_001_nu_01", 3)
      {s, cfg} = seed(dir, "020_001_nu_01")
      assert Work.missing(:bugfix, s, cfg) in 1..3

      # bundle parent -> 0 in v1 (mint scope is single-module parents)
      File.mkdir_p!(Path.join(dir, "021_001_xi_01"))

      File.write!(
        Path.join([dir, "021_001_xi_01", "solution.ex"]),
        "<file path=\"lib/a.ex\">\ndefmodule A do\n  def go(x), do: x + 1\nend\n</file>\n"
      )

      {s2, cfg2} = seed(dir, "021_001_xi_01")
      assert Work.missing(:bugfix, s2, cfg2) == 0
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
