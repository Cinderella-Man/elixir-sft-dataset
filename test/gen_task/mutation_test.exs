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

  describe "mutate/1" do
    test "guts every def/defp body of a plain module" do
      mutated = Mutation.mutate(@src)
      assert mutated =~ ~r/def add\(a, b\) do\s*raise/
      assert mutated =~ ~r/def sub\(a, b\) do\s*raise/
      assert mutated =~ ~r/defp helper\(x\) do\s*raise/
      refute mutated =~ "a + b"
      refute mutated =~ "x * 2"
    end

    test "returns source unchanged on a parse error (conservative → survives)" do
      assert Mutation.mutate("defmodule Broken do def") == "defmodule Broken do def"
    end

    test "blanks docs so an interpolated/heredoc @moduledoc round-trips to valid syntax" do
      # A moduledoc with interpolation + `iex>` code examples containing escaped quotes
      # is exactly the shape that broke Macro.to_string (task 096): the re-emitted mutant
      # was invalid syntax and failed to compile.
      src = ~S'''
      defmodule Doc do
        @allowed [:a, :b]
        @moduledoc """
        Allowed: #{inspect(@allowed)}.

        ## Examples

            iex> Doc.run("<a href=\"https://x\">y</a>")
            "y"
        """
        def run(x), do: x
      end
      '''

      mutated = Mutation.mutate(src)
      assert {:ok, _} = Code.string_to_quoted(mutated)
      assert mutated =~ ~r/def run\(x\) do\s*raise/
      assert mutated =~ "@moduledoc false"
    end

    @bundle """
    <file path="lib/app/math.ex">
    defmodule App.Math do
      def add(a, b), do: a + b
    end
    </file>

    <file path="lib/app/plug.ex">
    defmodule App.Plug do
      def init(opts), do: opts
      def call(conn, _opts), do: conn
    end
    </file>

    <file path="priv/repo/migrations/20240101000000_create.exs">
    defmodule App.Repo.Migrations.Create do
      def change, do: :ok
    end
    </file>
    """

    test "guts lib module bodies inside a <file> bundle, re-emitting a valid bundle" do
      mutated = Mutation.mutate(@bundle)

      assert EvalTask.Bundle.bundle?(mutated)
      # lib logic is gutted
      assert mutated =~ ~r/def add\(a, b\) do\s*raise/
      assert mutated =~ ~r/def call\(conn, _opts\) do\s*raise/
      refute mutated =~ "a + b"
    end

    test "leaves migrations (non-lib files) intact" do
      mutated = Mutation.mutate(@bundle)
      # the migration body must survive so the mutant still boots
      assert mutated =~ "def change, do: :ok"
    end

    test "leaves Plug `init/1` intact (it runs at compile time)" do
      mutated = Mutation.mutate(@bundle)
      assert mutated =~ ~r/def init\(opts\) do\s*opts\s*end/
      refute mutated =~ ~r/def init\(opts\) do\s*raise/
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

  describe "plug_module?/1" do
    test "recognizes Plug modules (use Plug / Plug.Builder)" do
      assert Mutation.plug_module?("defmodule P do\n  use Plug.Router\nend")
      assert Mutation.plug_module?("defmodule P do\n  use Plug.Builder\nend")
    end

    test "a GenServer is NOT exempt — its init/1 must be mutation-checked" do
      refute Mutation.plug_module?(
               "defmodule G do\n  use GenServer\n  def init(o), do: {:ok, o}\nend"
             )
    end
  end

  describe "gate_base/3 unbuildable mutant" do
    test "reports 'could not be constructed', not 'vacuous harness', on a parse error" do
      cfg = %GenTask.Config{per_fn_mutation: false}
      files = %{"solution.ex" => "def broken(", "test_harness.exs" => "irrelevant"}
      # The unparsable source short-circuits before any staging/eval subprocess runs.
      assert {:survived, why} = Mutation.gate_base("/nonexistent-must-not-be-used", files, cfg)
      assert why =~ "could not be constructed"
      refute why =~ "every function body is replaced"
    end
  end
end
