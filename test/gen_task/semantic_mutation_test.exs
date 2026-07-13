defmodule GenTask.SemanticMutationTest do
  use ExUnit.Case, async: true

  alias GenTask.Mutation

  @fixture """
  defmodule Demo do
    @moduledoc "true < false comparison words must stay untouched"

    @doc "returns {:ok, n} — this :ok must stay untouched"
    def clamp(n) when n > 10, do: {:ok, 10}
    def clamp(n), do: {:ok, n}

    def valid?(x), do: x >= 0 and true

    def label, do: "always true when n < 5"
  end
  """

  test "each operator class produces at least one mutant on the fixture" do
    labels = @fixture |> Mutation.semantic_mutants() |> Enum.map(&elem(&1, 0))

    assert Enum.any?(labels, &(&1 =~ "> -> >=")), "comparison swap missing: #{inspect(labels)}"
    assert Enum.any?(labels, &(&1 =~ "10 -> 11")), "int +1 missing"
    assert Enum.any?(labels, &(&1 =~ "10 -> 9")), "int -1 missing"
    assert Enum.any?(labels, &(&1 =~ ":ok")), ":ok↔:error missing"
    assert Enum.any?(labels, &(&1 =~ "true -> false")), "boolean flip missing"
  end

  test "every mutant parses and differs from the (doc-blanked) baseline" do
    mutants = Mutation.semantic_mutants(@fixture)
    assert mutants != []

    sources = Enum.map(mutants, &elem(&1, 1))

    for src <- sources do
      assert {:ok, _} = Code.string_to_quoted(src)
    end

    # one mutation per mutant → all mutants pairwise distinct
    assert length(Enum.uniq(sources)) == length(sources)
  end

  test "no mutation lands inside docs or string literals" do
    for {_label, src} <- Mutation.semantic_mutants(@fixture) do
      # the string literal must survive verbatim in every mutant
      assert src =~ "always true when n < 5"
    end
  end

  test "deterministic: same input, same output" do
    assert Mutation.semantic_mutants(@fixture) == Mutation.semantic_mutants(@fixture)
  end

  test "cap limits the mutant count and spreads rather than truncates" do
    all = Mutation.semantic_mutants(@fixture, 100)
    capped = Mutation.semantic_mutants(@fixture, 3)

    assert length(capped) == 3
    assert length(all) > 3
    # a spread, not a prefix: capped must not simply equal the first three
    refute capped == Enum.take(all, 3)
  end

  test "unparsable source yields no mutants" do
    assert Mutation.semantic_mutants("def oops do") == []
  end

  describe "T1.5 operators (min/max, arithmetic, div/rem)" do
    @t15_fixture """
    defmodule Arith do
      def clamp(n, cap), do: min(n, cap)
      def floor2(n), do: max(n, 2)
      def total(a, b), do: a + b
      def delta(a, b), do: a - b
      def scaled(a), do: a * 3
      def bucket(t, w), do: div(t, w)
      def phase(t, w), do: rem(t, w)
      def qualified(xs), do: Enum.min(xs)
    end
    """

    test "each new operator class produces its mutant, both AST and textual" do
      for mutants <- [
            Mutation.semantic_mutants(@t15_fixture),
            Mutation.semantic_mutants_textual(@t15_fixture)
          ] do
        labels = Enum.map(mutants, &elem(&1, 0))

        assert Enum.any?(labels, &(&1 =~ "min -> max")), "min swap missing: #{inspect(labels)}"
        assert Enum.any?(labels, &(&1 =~ "max -> min")), "max swap missing"
        assert Enum.any?(labels, &(&1 =~ "+ -> -")), "plus swap missing"
        assert Enum.any?(labels, &(&1 =~ "- -> +")), "minus swap missing"
        assert Enum.any?(labels, &(&1 =~ "* -> +")), "star swap missing"
        assert Enum.any?(labels, &(&1 =~ "div -> rem")), "div swap missing"
        assert Enum.any?(labels, &(&1 =~ "rem -> div")), "rem swap missing"
      end
    end

    test "textual mutants swap exactly the target call, one line, comments intact" do
      {_label, src} =
        @t15_fixture
        |> Mutation.semantic_mutants_textual()
        |> Enum.find(&(elem(&1, 0) =~ "div -> rem"))

      assert src =~ "def bucket(t, w), do: rem(t, w)"
      # the real rem site is untouched (one mutation per mutant)
      assert src =~ "def phase(t, w), do: rem(t, w)"
      assert length(String.split(src, "\n")) == length(String.split(@t15_fixture, "\n"))
    end

    test "qualified Enum.min and unary minus are never mutated" do
      labels =
        @t15_fixture |> Mutation.semantic_mutants() |> Enum.map(&elem(&1, 0))

      # Enum.min is on line 9 (the only min not bare) — no minmax label there
      refute Enum.any?(labels, &(&1 =~ ~r/L9.*min -> max/))

      neg = """
      defmodule Neg do
        def negate(x), do: -x
      end
      """

      refute Enum.any?(
               Mutation.semantic_mutants(neg),
               fn {label, _} -> label =~ "- -> +" end
             )
    end

    test "range endpoints are covered by the existing int operator" do
      src = """
      defmodule R do
        def window, do: Enum.to_list(1..5)
      end
      """

      labels = src |> Mutation.semantic_mutants() |> Enum.map(&elem(&1, 0))
      assert Enum.any?(labels, &(&1 =~ "5 -> 6"))
      assert Enum.any?(labels, &(&1 =~ "1 -> 2"))
    end
  end
end
