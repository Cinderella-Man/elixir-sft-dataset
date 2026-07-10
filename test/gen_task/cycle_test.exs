defmodule GenTask.CycleTest do
  use ExUnit.Case, async: true

  alias GenTask.Cycle

  @ctx %{id: "test_task", dir: "unused", mutant_dir: "unused"}

  @harness_3 """
  defmodule FooTest do
    use ExUnit.Case, async: false
    test "a", do: assert(1 == 1)
    test "b", do: assert(2 == 2)
    test "c", do: assert(3 == 3)
  end
  """

  @harness_2 """
  defmodule FooTest do
    use ExUnit.Case, async: false
    test "a", do: assert(1 == 1)
    test "b", do: assert(2 == 2)
  end
  """

  describe "guard_test_deletion/3" do
    test "rejects a fix whose harness has fewer tests" do
      files = %{"test_harness.exs" => @harness_3}
      upd = %{"test_harness.exs" => @harness_2}

      assert {:error, msg} = Cycle.guard_test_deletion(files, upd, @ctx)
      assert msg =~ "removed tests"
      assert msg =~ "3 → 2"
    end

    test "accepts a fix that keeps or grows the test count" do
      files = %{"test_harness.exs" => @harness_2}
      assert :ok = Cycle.guard_test_deletion(files, %{"test_harness.exs" => @harness_2}, @ctx)
      assert :ok = Cycle.guard_test_deletion(files, %{"test_harness.exs" => @harness_3}, @ctx)
    end

    test "accepts a fix that does not touch the harness" do
      files = %{"test_harness.exs" => @harness_3}

      assert :ok =
               Cycle.guard_test_deletion(files, %{"solution.ex" => "defmodule X do end"}, @ctx)
    end

    test "a flat→describe restructuring is not miscounted as deletion" do
      nested = """
      defmodule FooTest do
        use ExUnit.Case, async: false
        describe "group" do
          test "a", do: assert(1 == 1)
          test "b", do: assert(2 == 2)
          test "c", do: assert(3 == 3)
        end
      end
      """

      files = %{"test_harness.exs" => @harness_3}
      assert :ok = Cycle.guard_test_deletion(files, %{"test_harness.exs" => nested}, @ctx)
    end

    test "property blocks count as tests" do
      with_property = """
      defmodule FooTest do
        use ExUnit.Case, async: false
        use ExUnitProperties
        test "a", do: assert(1 == 1)
        test "b", do: assert(2 == 2)
        property "holds", do: assert(true)
      end
      """

      files = %{"test_harness.exs" => with_property}

      assert {:error, _} =
               Cycle.guard_test_deletion(files, %{"test_harness.exs" => @harness_2}, @ctx)
    end
  end

  describe "confirmation_seed/1 (stability confirmation, docs/12 item 6)" do
    test "is deterministic for a given task id" do
      assert Cycle.confirmation_seed("001_001_rate_limiter_01") ==
               Cycle.confirmation_seed("001_001_rate_limiter_01")
    end

    test "is nonzero (must differ from the evaluator's pinned seed 0)" do
      for id <- ["a", "001_001_x_01", "tfim_020_001_y_02", ""] do
        assert Cycle.confirmation_seed(id) > 0
      end
    end

    test "differs across task ids (order re-shuffled per task, not one global order)" do
      seeds = for id <- ["a", "b", "c", "d"], do: Cycle.confirmation_seed(id)
      assert length(Enum.uniq(seeds)) > 1
    end
  end

  describe "reason_text/1 for the new gate rejects" do
    test "names the flake seed" do
      assert Cycle.reason_text({:flaky, 42}) =~ "seed 42"
    end

    test "names the warning count" do
      assert Cycle.reason_text({:warnings, 2}) =~ "2"
    end
  end
end
