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
end
