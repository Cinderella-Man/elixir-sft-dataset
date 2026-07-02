defmodule GenTask.MutationTest do
  use ExUnit.Case, async: true

  alias GenTask.Mutation

  @src """
  defmodule Foo do
    @moduledoc "demo"

    def add(a, b), do: a + b
    def sub(a, b), do: a - b
    defp helper(x), do: x * 2
    def double(x), do: helper(x)
  end
  """

  describe "public_functions/1" do
    test "lists public defs (name/arity), not private ones, de-duplicated" do
      fns = Mutation.public_functions(@src)
      assert {:add, 2} in fns
      assert {:sub, 2} in fns
      assert {:double, 1} in fns
      refute {:helper, 1} in fns
    end

    test "returns [] on unparseable source" do
      assert Mutation.public_functions("def broken(") == []
    end

    test "de-duplicates multi-clause functions" do
      src = """
      defmodule Bar do
        def f(0), do: :zero
        def f(n), do: n
      end
      """

      assert Mutation.public_functions(src) == [{:f, 1}]
    end
  end

  describe "mutate_fn/3" do
    test "replaces only the target function's body with raise" do
      mutated = Mutation.mutate_fn(@src, :add, 2)
      # add/2 is gutted...
      assert mutated =~ ~r/def add\(a, b\) do\s*raise/
      # ...but sub/2 is untouched
      assert mutated =~ "a - b"
    end

    test "leaves other arities of the same name intact" do
      src = """
      defmodule Baz do
        def f(a), do: a
        def f(a, b), do: a + b
      end
      """

      mutated = Mutation.mutate_fn(src, :f, 1)
      assert mutated =~ ~r/def f\(a\) do\s*raise/
      assert mutated =~ "a + b"
    end

    test "returns source unchanged on a parse error" do
      assert Mutation.mutate_fn("def broken(", :x, 0) == "def broken("
    end

    test "mutates a private function when kind: :defp is given" do
      mutated = Mutation.mutate_fn(@src, :helper, 1, :defp)
      assert mutated =~ ~r/defp helper\(x\) do\s*raise/
      # public defs untouched
      assert mutated =~ "a + b"
      # a :def mutate of the same name/arity is a no-op (helper is private)
      assert Mutation.mutate_fn(@src, :helper, 1, :def) =~ "x * 2"
    end
  end

  describe "all_functions/1" do
    test "lists public AND private functions with their kind" do
      fns = Mutation.all_functions(@src)
      assert {:def, :add, 2} in fns
      assert {:def, :sub, 2} in fns
      assert {:def, :double, 1} in fns
      assert {:defp, :helper, 1} in fns
    end

    test "[] on a parse error" do
      assert Mutation.all_functions("defmodule Broken do def") == []
    end
  end
end
