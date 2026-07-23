# The tests are the spec

Below is a complete, self-contained ExUnit suite. It is the only
specification you get: build the module (or modules) it exercises until
every test passes. Reach for nothing beyond what the tests themselves
require — the standard library and OTP unless the suite says otherwise.
House style applies (`@moduledoc`, `@doc` + `@spec` on the public API,
no compiler warnings).

## The test suite

```elixir
defmodule FuzzyIndexTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} = FuzzyIndex.start_link([])
    %{idx: pid}
  end

  # -------------------------------------------------------
  # Exact keyword search
  # -------------------------------------------------------

  test "indexes documents and finds them by exact keyword", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "the quick brown fox")
    :ok = FuzzyIndex.index(idx, "doc2", "the lazy dog")

    results = FuzzyIndex.search(idx, "fox")
    assert length(results) == 1
    assert hd(results).id == "doc1"
  end

  # -------------------------------------------------------
  # Fuzzy matching within the default distance
  # -------------------------------------------------------

  test "a typo within edit distance 1 still matches by default", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "quick brown fox")
    :ok = FuzzyIndex.index(idx, "doc2", "slow green turtle")

    # "quik" is edit distance 1 from "quick" and far from every other term
    results = FuzzyIndex.search(idx, "quik")
    assert Enum.map(results, & &1.id) == ["doc1"]
  end

  test "max_distance option widens or narrows fuzzy matching", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "banana")

    # "banan" is distance 1 from "banana" → matches by default
    assert Enum.map(FuzzyIndex.search(idx, "banan"), & &1.id) == ["doc1"]

    # "bana" is distance 2 from "banana" → no match at the default max_distance of 1
    assert FuzzyIndex.search(idx, "bana") == []

    # ... but matches when max_distance is raised to 2
    assert Enum.map(FuzzyIndex.search(idx, "bana", max_distance: 2), & &1.id) == ["doc1"]
  end

  # -------------------------------------------------------
  # Scoring: exact beats fuzzy, frequency matters
  # -------------------------------------------------------

  test "exact matches outrank near-miss matches", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "color color")
    :ok = FuzzyIndex.index(idx, "doc2", "colour")

    results = FuzzyIndex.search(idx, "color")
    assert Enum.map(results, & &1.id) == ["doc1", "doc2"]

    # doc1: exact "color" (similarity 2) occurring twice → 2 * 2 = 4
    # doc2: near "colour" at distance 1 (similarity 1) occurring once → 1 * 1 = 1
    assert Enum.find(results, &(&1.id == "doc1")).score == 4
    assert Enum.find(results, &(&1.id == "doc2")).score == 1
  end

  test "higher term frequency yields a higher score", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "data data data")
    :ok = FuzzyIndex.index(idx, "doc2", "data")

    results = FuzzyIndex.search(idx, "data")
    assert Enum.map(results, & &1.id) == ["doc1", "doc2"]
    # doc1: similarity 2 * count 3 = 6 ; doc2: similarity 2 * count 1 = 2
    assert Enum.find(results, &(&1.id == "doc1")).score == 6
    assert Enum.find(results, &(&1.id == "doc2")).score == 2
  end

  test "multiple query terms sum their contributions", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "quick brown fox")

    [result] = FuzzyIndex.search(idx, "quick fox")
    assert result.id == "doc1"
    # each exact term contributes similarity 2 * count 1; 2 + 2 = 4
    assert result.score == 4
  end

  # -------------------------------------------------------
  # Stop words
  # -------------------------------------------------------

  test "stop words are not searchable", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "the cat sat")

    assert FuzzyIndex.search(idx, "the") == []
    assert length(FuzzyIndex.search(idx, "cat")) == 1
  end

  test "custom stop words override the defaults" do
    {:ok, idx} = FuzzyIndex.start_link(stop_words: MapSet.new(["foo", "bar"]))

    :ok = FuzzyIndex.index(idx, "doc1", "foo baz bar qux")
    :ok = FuzzyIndex.index(idx, "doc2", "the quick")

    # "foo" and "bar" are stop words under the custom set
    assert FuzzyIndex.search(idx, "foo") == []
    assert FuzzyIndex.search(idx, "bar") == []

    # "the" is NOT a stop word under the custom set, so it is indexed
    assert length(FuzzyIndex.search(idx, "the")) == 1
  end

  # -------------------------------------------------------
  # Punctuation and tokenization
  # -------------------------------------------------------

  test "punctuation is stripped and produces no empty terms", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "Hello, world!")

    # splitting on ~r/[^a-z0-9]+/ yields exactly ["hello", "world"]
    assert FuzzyIndex.stats(idx).term_count == 2
    assert length(FuzzyIndex.search(idx, "hello")) == 1
    assert length(FuzzyIndex.search(idx, "world")) == 1
  end

  # -------------------------------------------------------
  # Stats
  # -------------------------------------------------------

  test "stats reflects document and vocabulary counts", %{idx: idx} do
    assert %{document_count: 0, term_count: 0} = FuzzyIndex.stats(idx)

    :ok = FuzzyIndex.index(idx, "doc1", "alpha beta gamma")
    stats = FuzzyIndex.stats(idx)
    assert stats.document_count == 1
    assert stats.term_count == 3

    :ok = FuzzyIndex.index(idx, "doc2", "beta gamma delta")
    stats = FuzzyIndex.stats(idx)
    assert stats.document_count == 2
    assert stats.term_count == 4
  end

  # -------------------------------------------------------
  # terms_like
  # -------------------------------------------------------

  test "terms_like returns vocabulary within distance, sorted by distance then alpha", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "cat cot cats dog")

    # distances from "cat": cat=0, cot=1, cats=1, dog=3 (excluded at max 1)
    # tie at distance 1 broken alphabetically: "cats" < "cot"
    assert FuzzyIndex.terms_like(idx, "cat", 1) == ["cat", "cats", "cot"]
  end

  test "terms_like excludes terms beyond the distance and lowercases its input", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "color")
    :ok = FuzzyIndex.index(idx, "doc2", "colour")
    :ok = FuzzyIndex.index(idx, "doc3", "cold")

    # color=0, colour=1, cold=2 (excluded at max 1); input "COLOR" is lowercased
    assert FuzzyIndex.terms_like(idx, "COLOR", 1) == ["color", "colour"]
  end

  test "terms_like defaults to max distance 1", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "banana")

    assert FuzzyIndex.terms_like(idx, "banan") == ["banana"]
    assert FuzzyIndex.terms_like(idx, "bana") == []
  end

  # -------------------------------------------------------
  # Removal
  # -------------------------------------------------------

  test "removed document no longer appears and vocabulary shrinks", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "alpha beta")
    :ok = FuzzyIndex.index(idx, "doc2", "beta gamma")
    :ok = FuzzyIndex.index(idx, "doc3", "gamma delta")

    assert FuzzyIndex.stats(idx).document_count == 3

    :ok = FuzzyIndex.remove(idx, "doc2")

    assert FuzzyIndex.stats(idx).document_count == 2

    # "beta" now only in doc1, "gamma" now only in doc3
    assert Enum.map(FuzzyIndex.search(idx, "beta"), & &1.id) == ["doc1"]
    assert Enum.map(FuzzyIndex.search(idx, "gamma"), & &1.id) == ["doc3"]

    # vocabulary is alpha, beta, gamma, delta
    assert FuzzyIndex.stats(idx).term_count == 4
  end

  test "removal drops vocabulary terms held only by the removed document", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "alpha beta")
    :ok = FuzzyIndex.index(idx, "doc2", "beta gamma delta")

    # vocabulary is alpha, beta, gamma, delta
    assert FuzzyIndex.stats(idx).term_count == 4

    :ok = FuzzyIndex.remove(idx, "doc2")

    # "gamma" and "delta" appear in no remaining document, so they leave the
    # vocabulary; "beta" survives in doc1
    assert FuzzyIndex.stats(idx).term_count == 2
    assert FuzzyIndex.terms_like(idx, "gamma", 0) == []
    assert FuzzyIndex.terms_like(idx, "delta", 0) == []
    assert FuzzyIndex.terms_like(idx, "beta", 0) == ["beta"]
  end

  test "re-indexing drops vocabulary terms no other document holds", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "alpha beta")
    :ok = FuzzyIndex.index(idx, "doc2", "beta gamma")

    assert FuzzyIndex.stats(idx).term_count == 3

    # doc2's only unique term, "gamma", is replaced by "delta"
    :ok = FuzzyIndex.index(idx, "doc2", "beta delta")

    assert FuzzyIndex.stats(idx).term_count == 3
    assert FuzzyIndex.terms_like(idx, "gamma", 0) == []
    assert FuzzyIndex.terms_like(idx, "delta", 0) == ["delta"]
  end

  test "removing a non-existent document does not raise", %{idx: idx} do
    assert :ok = FuzzyIndex.remove(idx, "nonexistent")
  end

  # -------------------------------------------------------
  # Re-indexing (update)
  # -------------------------------------------------------

  test "re-indexing replaces previous content", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "apple banana")
    assert length(FuzzyIndex.search(idx, "apple")) == 1

    :ok = FuzzyIndex.index(idx, "doc1", "delta epsilon")

    assert FuzzyIndex.search(idx, "apple") == []
    assert Enum.map(FuzzyIndex.search(idx, "delta"), & &1.id) == ["doc1"]
    assert FuzzyIndex.stats(idx).document_count == 1
    assert FuzzyIndex.stats(idx).term_count == 2
  end

  # -------------------------------------------------------
  # Limit
  # -------------------------------------------------------

  test "limit caps the number of returned results", %{idx: idx} do
    for i <- 1..20 do
      :ok = FuzzyIndex.index(idx, "doc#{i}", "keyword variation#{i} extra text")
    end

    assert length(FuzzyIndex.search(idx, "keyword", limit: 5)) == 5
    assert length(FuzzyIndex.search(idx, "keyword")) == 20
  end

  # -------------------------------------------------------
  # Empty index
  # -------------------------------------------------------

  test "search on an empty index returns an empty list", %{idx: idx} do
    assert FuzzyIndex.search(idx, "anything") == []
  end

  # -------------------------------------------------------
  # Named registration
  # -------------------------------------------------------

  test "accepts a :name option for registration" do
    {:ok, _pid} = FuzzyIndex.start_link(name: :fuzzy_index_reg)

    :ok = FuzzyIndex.index(:fuzzy_index_reg, "doc1", "hello world")
    assert length(FuzzyIndex.search(:fuzzy_index_reg, "hello")) == 1
  end

  test "repeated query terms do not multiply a document's score", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "data data")

    [once] = FuzzyIndex.search(idx, "data")
    [thrice] = FuzzyIndex.search(idx, "data data data")

    # exact "data" (similarity 2) occurring twice → 2 * 2 = 4, counted a single time
    assert once.score == 4
    assert thrice.score == 4
  end

  test "contribution takes the max over matching terms rather than summing them", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "color colour")

    [result] = FuzzyIndex.search(idx, "color")

    # exact "color" → 2 * 1 = 2 ; near "colour" → 1 * 1 = 1 ; max is 2, not the sum 3
    assert result.score == 2
  end

  test "limit keeps the highest scoring results, not arbitrary ones", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "low", "keyword")
    :ok = FuzzyIndex.index(idx, "mid", "keyword keyword")
    :ok = FuzzyIndex.index(idx, "high", "keyword keyword keyword")

    assert Enum.map(FuzzyIndex.search(idx, "keyword", limit: 1), & &1.id) == ["high"]
    assert Enum.map(FuzzyIndex.search(idx, "keyword", limit: 2), & &1.id) == ["high", "mid"]
  end

  test "similarity scales with max_distance for exact and maximally distant matches", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "banana")

    # exact match at max_distance 2 → similarity 3, count 1 → score 3
    [exact] = FuzzyIndex.search(idx, "banana", max_distance: 2)
    assert exact.score == 3

    # "bana" is distance 2 from "banana", the maximum allowed → similarity 1 → score 1
    [edge] = FuzzyIndex.search(idx, "bana", max_distance: 2)
    assert edge.score == 1
  end

  test "every documented default stop word is dropped during tokenization", %{idx: idx} do
    text =
      "the a an is are was were in on at to of and or it this that for with as by " <>
        "not be has had have do does did but if from marker"

    :ok = FuzzyIndex.index(idx, "doc1", text)

    assert FuzzyIndex.stats(idx).term_count == 1
    assert FuzzyIndex.terms_like(idx, "marker", 0) == ["marker"]
  end

  test "uppercase text and uppercase queries match each other", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "HELLO World")

    assert Enum.map(FuzzyIndex.search(idx, "HELLO"), & &1.id) == ["doc1"]
    assert Enum.map(FuzzyIndex.search(idx, "WoRlD"), & &1.id) == ["doc1"]
    assert FuzzyIndex.terms_like(idx, "HELLO", 0) == ["hello"]
  end
end
```

Send back the implementation only — one file, no tests.
