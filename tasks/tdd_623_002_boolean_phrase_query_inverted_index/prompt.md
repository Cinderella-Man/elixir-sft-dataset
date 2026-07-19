# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule InvertedIndexTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} = InvertedIndex.start_link([])
    %{idx: pid}
  end

  # -------------------------------------------------------
  # Basic term search
  # -------------------------------------------------------

  test "term query finds documents containing the token", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "the quick brown fox"})
    :ok = InvertedIndex.index(idx, "b", %{body: "the quick brown cat"})
    :ok = InvertedIndex.index(idx, "c", %{body: "a slow green turtle"})

    assert InvertedIndex.search(idx, {:term, "fox"}) == ["a"]
    assert InvertedIndex.search(idx, {:term, "quick"}) == ["a", "b"]
  end

  test "term query is case-insensitive", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "Quick Brown Fox"})
    assert InvertedIndex.search(idx, {:term, "FOX"}) == ["a"]
  end

  test "term query for a stop word matches nothing", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "the cat on the mat"})
    assert InvertedIndex.search(idx, {:term, "the"}) == []
    assert InvertedIndex.search(idx, {:term, "cat"}) == ["a"]
  end

  # -------------------------------------------------------
  # Boolean operators
  # -------------------------------------------------------

  test "and returns intersection", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "quick brown fox"})
    :ok = InvertedIndex.index(idx, "b", %{body: "quick brown cat"})
    :ok = InvertedIndex.index(idx, "c", %{body: "slow green turtle"})

    result = InvertedIndex.search(idx, {:and, [{:term, "quick"}, {:term, "brown"}]})
    assert result == ["a", "b"]

    result2 = InvertedIndex.search(idx, {:and, [{:term, "quick"}, {:term, "fox"}]})
    assert result2 == ["a"]
  end

  test "or returns union", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "quick brown fox"})
    :ok = InvertedIndex.index(idx, "b", %{body: "quick brown cat"})
    :ok = InvertedIndex.index(idx, "c", %{body: "slow green turtle"})

    result = InvertedIndex.search(idx, {:or, [{:term, "fox"}, {:term, "turtle"}]})
    assert result == ["a", "c"]
  end

  test "not excludes matching documents", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "quick brown fox"})
    :ok = InvertedIndex.index(idx, "b", %{body: "quick brown cat"})
    :ok = InvertedIndex.index(idx, "c", %{body: "slow green turtle"})

    assert InvertedIndex.search(idx, {:not, {:term, "fox"}}) == ["b", "c"]
  end

  test "empty and matches all, empty or matches none", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "quick brown fox"})
    :ok = InvertedIndex.index(idx, "b", %{body: "slow turtle"})

    assert InvertedIndex.search(idx, {:and, []}) == ["a", "b"]
    assert InvertedIndex.search(idx, {:or, []}) == []
  end

  test "nested boolean expressions evaluate correctly", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "the quick brown fox"})
    :ok = InvertedIndex.index(idx, "b", %{body: "the quick brown cat"})
    :ok = InvertedIndex.index(idx, "c", %{body: "a slow green turtle"})
    :ok = InvertedIndex.index(idx, "d", %{body: "fox jumps high"})

    # (cat OR fox) AND (NOT quick)  ->  only "d"
    query = {:and, [{:or, [{:term, "cat"}, {:term, "fox"}]}, {:not, {:term, "quick"}}]}
    assert InvertedIndex.search(idx, query) == ["d"]
  end

  # -------------------------------------------------------
  # Result ordering
  # -------------------------------------------------------

  test "results are sorted ascending by id", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "c", %{body: "keyword"})
    :ok = InvertedIndex.index(idx, "a", %{body: "keyword"})
    :ok = InvertedIndex.index(idx, "b", %{body: "keyword"})

    assert InvertedIndex.search(idx, {:term, "keyword"}) == ["a", "b", "c"]
  end

  # -------------------------------------------------------
  # Phrase queries
  # -------------------------------------------------------

  test "phrase matches consecutive terms", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "the quick brown fox"})
    :ok = InvertedIndex.index(idx, "b", %{body: "the quick brown cat"})

    assert InvertedIndex.search(idx, {:phrase, "quick brown"}) == ["a", "b"]
    assert InvertedIndex.search(idx, {:phrase, "brown fox"}) == ["a"]
  end

  test "phrase does not match non-consecutive terms", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "the quick brown fox"})
    # "quick" and "fox" both appear but are not adjacent
    assert InvertedIndex.search(idx, {:phrase, "quick fox"}) == []
  end

  test "phrase must lie within a single field", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "d", %{title: "quick", body: "brown cat"})

    # "quick" is in title, "brown" is in body -> not a single-field phrase
    assert InvertedIndex.search(idx, {:phrase, "quick brown"}) == []
    # but each term individually is findable in some field
    assert InvertedIndex.search(idx, {:term, "quick"}) == ["d"]
  end

  test "stop words in a phrase are dropped before matching", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "quick brown fox"})
    # "the" is a stop word: phrase tokenizes to ["brown", "fox"] which is consecutive
    assert InvertedIndex.search(idx, {:phrase, "brown the fox"}) == ["a"]
  end

  test "single-term phrase behaves like a term query", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{title: "fox", body: "hunting"})
    assert InvertedIndex.search(idx, {:phrase, "fox"}) == ["a"]
  end

  # -------------------------------------------------------
  # Stats
  # -------------------------------------------------------

  test "stats reflects document and term counts", %{idx: idx} do
    assert %{document_count: 0, term_count: 0} = InvertedIndex.stats(idx)

    :ok = InvertedIndex.index(idx, "a", %{body: "the quick brown fox"})
    stats = InvertedIndex.stats(idx)
    assert stats.document_count == 1
    assert stats.term_count == 3

    :ok = InvertedIndex.index(idx, "b", %{body: "the quick brown cat"})
    stats = InvertedIndex.stats(idx)
    assert stats.document_count == 2
    assert stats.term_count == 4
  end

  # -------------------------------------------------------
  # Custom stop words
  # -------------------------------------------------------

  test "custom stop words override the defaults", _ctx do
    {:ok, idx} = InvertedIndex.start_link(stop_words: MapSet.new(["foo", "bar"]))

    :ok = InvertedIndex.index(idx, "a", %{body: "foo baz bar qux"})
    :ok = InvertedIndex.index(idx, "b", %{body: "the quick brown"})

    assert InvertedIndex.search(idx, {:term, "foo"}) == []
    assert InvertedIndex.search(idx, {:term, "bar"}) == []
    # "the" is NOT a stop word under the custom set
    assert InvertedIndex.search(idx, {:term, "the"}) == ["b"]
  end

  # -------------------------------------------------------
  # Removal and re-indexing
  # -------------------------------------------------------

  test "removed document no longer appears", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "quick brown fox"})
    :ok = InvertedIndex.index(idx, "b", %{body: "quick brown cat"})
    :ok = InvertedIndex.index(idx, "c", %{body: "slow turtle"})

    :ok = InvertedIndex.remove(idx, "b")

    assert InvertedIndex.search(idx, {:term, "quick"}) == ["a"]
    assert InvertedIndex.stats(idx).document_count == 2
  end

  test "removing non-existent doc does not raise", %{idx: idx} do
    assert :ok = InvertedIndex.remove(idx, "nonexistent")
  end

  test "re-indexing replaces previous content", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "apple banana cherry"})
    assert InvertedIndex.search(idx, {:term, "apple"}) == ["a"]

    :ok = InvertedIndex.index(idx, "a", %{body: "delta epsilon zeta"})
    assert InvertedIndex.search(idx, {:term, "apple"}) == []
    assert InvertedIndex.search(idx, {:term, "delta"}) == ["a"]
    assert InvertedIndex.stats(idx).document_count == 1
  end

  # -------------------------------------------------------
  # Prefix suggestion
  # -------------------------------------------------------

  test "suggest returns prefix matches sorted by document frequency", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "d1", %{body: "programming program problems"})
    :ok = InvertedIndex.index(idx, "d2", %{body: "program productivity projects"})
    :ok = InvertedIndex.index(idx, "d3", %{body: "testing productivity"})

    suggestions = InvertedIndex.suggest(idx, "pro")
    assert Enum.all?(suggestions, &String.starts_with?(&1, "pro"))

    # "program" (2 docs) and "productivity" (2 docs) rank above the 1-doc terms
    top_two = Enum.take(suggestions, 2)
    assert "program" in top_two
    assert "productivity" in top_two
  end

  test "suggest respects limit and is case-insensitive", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "d1", %{body: "programming program problems"})
    :ok = InvertedIndex.index(idx, "d2", %{body: "program productivity projects"})

    assert length(InvertedIndex.suggest(idx, "pro", 2)) == 2
    assert length(InvertedIndex.suggest(idx, "PRO")) > 0
  end

  test "suggest without a limit returns at most 10 terms", %{idx: idx} do
    words = Enum.map_join(1..12, " ", fn i -> "pre#{i}" end)
    :ok = InvertedIndex.index(idx, "d1", %{body: words})

    suggestions = InvertedIndex.suggest(idx, "pre")
    assert length(suggestions) == 10
    assert Enum.all?(suggestions, &String.starts_with?(&1, "pre"))
  end

  test "suggest returns empty list for non-matching prefix", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "d1", %{body: "alpha beta gamma"})
    assert InvertedIndex.suggest(idx, "xyz") == []
  end

  # -------------------------------------------------------
  # Edge cases and tokenization
  # -------------------------------------------------------

  test "search on empty index returns empty list", %{idx: idx} do
    assert InvertedIndex.search(idx, {:term, "anything"}) == []
    assert InvertedIndex.search(idx, {:phrase, "any thing"}) == []
  end

  test "punctuation is stripped during tokenization", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "Hello, world! This is a test."})
    assert InvertedIndex.search(idx, {:term, "hello"}) == ["a"]
    assert InvertedIndex.search(idx, {:term, "world"}) == ["a"]
    assert InvertedIndex.search(idx, {:phrase, "hello world"}) == ["a"]
  end

  test "accepts :name option for registration" do
    {:ok, _pid} = InvertedIndex.start_link(name: :bool_index)
    :ok = InvertedIndex.index(:bool_index, "a", %{body: "hello world"})
    assert InvertedIndex.search(:bool_index, {:term, "hello"}) == ["a"]
  end

  test "term query with multi-token word uses only the first token", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "quick brown fox"})
    :ok = InvertedIndex.index(idx, "b", %{body: "quick green turtle"})
    :ok = InvertedIndex.index(idx, "c", %{body: "slow brown bear"})

    # tokenizes to ["quick", "brown"]; only "quick" is used
    assert InvertedIndex.search(idx, {:term, "quick brown"}) == ["a", "b"]
    # punctuation-separated form tokenizes the same way
    assert InvertedIndex.search(idx, {:term, "quick, brown!"}) == ["a", "b"]
  end

  test "phrase of only stop words matches no documents", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "the quick brown fox"})
    :ok = InvertedIndex.index(idx, "b", %{body: "is on at the of"})

    assert InvertedIndex.search(idx, {:phrase, "the is of"}) == []
    assert InvertedIndex.search(idx, {:phrase, "!!! ,,,"}) == []
    assert InvertedIndex.search(idx, {:phrase, ""}) == []
  end

  test "removed document drops its exclusive terms from the vocabulary", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "quick brown fox"})
    :ok = InvertedIndex.index(idx, "b", %{body: "quick brown cat"})
    assert InvertedIndex.stats(idx).term_count == 4

    :ok = InvertedIndex.remove(idx, "a")

    assert InvertedIndex.search(idx, {:term, "fox"}) == []
    assert InvertedIndex.search(idx, {:phrase, "brown fox"}) == []
    assert InvertedIndex.suggest(idx, "fo") == []
    assert InvertedIndex.stats(idx).term_count == 3
  end

  test "every documented default stop word is excluded from the index", _ctx do
    {:ok, idx} = InvertedIndex.start_link([])

    defaults = ~w(the a an is are was were in on at to of and or it this that for with
                as by not be has had have do does did but if from)

    text = Enum.join(defaults, " ") <> " sentinel"
    :ok = InvertedIndex.index(idx, "a", %{body: text})

    assert InvertedIndex.stats(idx).term_count == 1
    assert InvertedIndex.search(idx, {:term, "sentinel"}) == ["a"]

    for word <- defaults do
      assert InvertedIndex.search(idx, {:term, word}) == [], "#{word} was indexed"
    end
  end

  test "re-indexing removes the old version's terms from the vocabulary", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{title: "apple pie", body: "apple banana"})
    assert InvertedIndex.stats(idx).term_count == 3

    :ok = InvertedIndex.index(idx, "a", %{body: "cherry"})

    assert InvertedIndex.stats(idx) == %{document_count: 1, term_count: 1}
    assert InvertedIndex.suggest(idx, "app") == []
    assert InvertedIndex.search(idx, {:phrase, "apple pie"}) == []
    assert InvertedIndex.search(idx, {:term, "cherry"}) == ["a"]
  end

  test "term query matches a token found in any field of the document", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{title: "alpha", body: "beta", notes: "gamma"})
    :ok = InvertedIndex.index(idx, "b", %{title: "beta", body: "delta"})

    assert InvertedIndex.search(idx, {:term, "alpha"}) == ["a"]
    assert InvertedIndex.search(idx, {:term, "gamma"}) == ["a"]
    assert InvertedIndex.search(idx, {:term, "beta"}) == ["a", "b"]
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
