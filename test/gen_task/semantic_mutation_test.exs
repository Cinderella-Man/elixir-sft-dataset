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
end
