defmodule GenTask.VariationDistinctnessTest do
  # The pre-cycle variation-distinctness gate (docs/12 §5.1 item 4): a variation whose
  # co-authored solution has the SAME public-function set as the base or an accepted
  # sibling is rejected BEFORE the blind solve + grading cycle.
  use ExUnit.Case, async: true

  alias GenTask.{Config, Variations}

  @base_src """
  defmodule RateLimiter do
    def start_link(opts), do: opts
    def allow?(key), do: key
    def reset(key), do: key
  end
  """

  # Same public-function set as @base_src, different body/module name.
  @clone_src """
  defmodule SlidingLimiter do
    def start_link(o), do: {:ok, o}
    def allow?(k), do: true and k != nil
    def reset(k), do: {:reset, k}
  end
  """

  @distinct_src """
  defmodule Histogram do
    def record(value), do: value
    def percentile(p), do: p
  end
  """

  defp set(src), do: src |> GenTask.Mutation.public_functions() |> MapSet.new()

  describe "duplicate_public_fn_set?/2" do
    test "true when the variation's public-fn set equals a taken set" do
      assert Variations.duplicate_public_fn_set?(@clone_src, [set(@base_src)])
    end

    test "false when the sets differ" do
      refute Variations.duplicate_public_fn_set?(@distinct_src, [set(@base_src)])
    end

    test "false when nothing is taken yet" do
      refute Variations.duplicate_public_fn_set?(@clone_src, [])
    end

    test "an empty/unparseable solution never collides (nothing to compare)" do
      refute Variations.duplicate_public_fn_set?(nil, [set(@base_src)])
      refute Variations.duplicate_public_fn_set?("def broken(", [set(@base_src)])
      refute Variations.duplicate_public_fn_set?(@clone_src, [MapSet.new()])
    end

    test "arity matters: same names at different arities are distinct" do
      other_arity = """
      defmodule L do
        def start_link(a, b), do: {a, b}
        def allow?(k), do: k
        def reset(k), do: k
      end
      """

      refute Variations.duplicate_public_fn_set?(other_arity, [set(@base_src)])
    end
  end

  describe "taken_public_fn_sets/2" do
    setup do
      tmp =
        Path.join(System.tmp_dir!(), "vdist_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)
      {:ok, tmp: tmp}
    end

    test "includes the base's set and every on-disk sibling's set", %{tmp: tmp} do
      sib = Path.join(tmp, "007_002_sliding_window_01")
      File.mkdir_p!(sib)
      File.write!(Path.join(sib, "solution.ex"), @distinct_src)

      base = %{num: 7, files: %{"solution.ex" => @base_src}}
      taken = Variations.taken_public_fn_sets(base, %Config{tasks_dir: tmp})

      assert set(@base_src) in taken
      assert set(@distinct_src) in taken
      assert length(taken) == 2
    end

    test "drops empty sets (bundle base / no public defs)", %{tmp: tmp} do
      base = %{num: 7, files: %{"solution.ex" => "defmodule E do\n  defp p(x), do: x\nend"}}
      assert Variations.taken_public_fn_sets(base, %Config{tasks_dir: tmp}) == []
    end
  end
  describe "prompt carries the gate criterion" do
    test "Prompts.variations lists every taken public-API set as a hard constraint" do
      {_system, user} =
        GenTask.Prompts.variations(
          %{num: 34, name: "data reconciliation engine"},
          %{"prompt.md" => "p", "solution.ex" => "s", "test_harness.exs" => "h"},
          "## catalog",
          3,
          ["existing variation"],
          ["reconcile/3", "diff/2, merge/2"]
        )

      assert user =~ "HARD CONSTRAINT"
      assert user =~ "{reconcile/3}"
      assert user =~ "{diff/2, merge/2}"
      assert user =~ "existing variation"
    end

    test "no constraint block when nothing is taken" do
      {_system, user} =
        GenTask.Prompts.variations(
          %{num: 34, name: "x"},
          %{"prompt.md" => "p", "solution.ex" => "s", "test_harness.exs" => "h"},
          "## catalog"
        )

      refute user =~ "HARD CONSTRAINT"
    end
  end
end
