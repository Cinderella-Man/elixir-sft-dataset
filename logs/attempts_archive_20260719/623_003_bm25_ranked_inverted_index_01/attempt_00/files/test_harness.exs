defmodule InvertedIndexTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} = InvertedIndex.start_link([])
    %{idx: pid}
  end

  # -------------------------------------------------------
  # Basic indexing and search
  # -------------------------------------------------------

  test "indexes documents and finds them by keyword", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "the quick brown fox jumps over the lazy dog"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "the quick brown cat sits on the mat"})
    :ok = InvertedIndex.index(idx, "doc3", %{body: "a slow green turtle crosses the road"})

    results = InvertedIndex.search(idx, "fox")
    assert length(results) == 1
    assert hd(results).id == "doc1"
  end

  test "multi-term search returns all matching documents", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "the quick brown fox"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "the quick brown cat"})
    :ok = InvertedIndex.index(idx, "doc3", %{body: "a slow green turtle"})

    ids = InvertedIndex.search(idx, "quick brown") |> Enum.map(& &1.id)
    assert length(ids) == 2
    assert "doc1" in ids
    assert "doc2" in ids
  end

  # -------------------------------------------------------
  # Stats
  # -------------------------------------------------------

  test "stats reflects document and term counts", %{idx: idx} do
    assert %{document_count: 0, term_count: 0} = InvertedIndex.stats(idx)

    :ok = InvertedIndex.index(idx, "doc1", %{body: "alpha beta gamma"})
    assert InvertedIndex.stats(idx).document_count == 1
    assert InvertedIndex.stats(idx).term_count == 3

    :ok = InvertedIndex.index(idx, "doc2", %{body: "beta gamma delta"})
    assert InvertedIndex.stats(idx).document_count == 2
    assert InvertedIndex.stats(idx).term_count == 4
  end

  # -------------------------------------------------------
  # Exact BM25 value with default parameters
  # -------------------------------------------------------

  test "exact BM25 score with default k1 and b", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "fox fox cat"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "dog bird"})

    # N=2, df(fox)=1 -> IDF = ln(1 + 1.5/1.5) = ln 2
    # f=2, |d|=3, avgdl=2.5, k1=1.2, b=0.75
    # denom = 2 + 1.2*(1 - 0.75 + 0.75*3/2.5) = 3.38 ; numer = 2*2.2 = 4.4
    # score = ln 2 * 4.4/3.38
    [result] = InvertedIndex.search(idx, "fox")
    assert result.id == "doc1"
    expected = :math.log(2) * 4.4 / 3.38
    assert_in_delta result.score, expected, 1.0e-9
  end

  test "custom k1 and b change the score as specified", _ctx do
    {:ok, idx} = InvertedIndex.start_link(k1: 2.0, b: 0.0)
    :ok = InvertedIndex.index(idx, "doc1", %{body: "fox fox cat"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "dog bird"})

    # b=0 removes length normalization: denom = f + k1 = 2 + 2 = 4 ; numer = f*(k1+1) = 6
    # IDF = ln 2 ; score = ln 2 * 6/4 = ln 2 * 1.5
    [result] = InvertedIndex.search(idx, "fox")
    assert_in_delta result.score, :math.log(2) * 1.5, 1.0e-9
  end

  # -------------------------------------------------------
  # BM25 term-frequency saturation
  # -------------------------------------------------------

  test "term frequency saturates rather than scaling linearly", %{idx: idx} do
    # both docs have length 4, so length normalization is identical
    :ok = InvertedIndex.index(idx, "doc1", %{body: "fox fox fox fox"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "fox cat dog bird"})

    results = InvertedIndex.search(idx, "fox")
    d1 = Enum.find(results, &(&1.id == "doc1"))
    d2 = Enum.find(results, &(&1.id == "doc2"))

    # 4x the raw term frequency must NOT give ~4x the score (saturation)
    assert d1.score > d2.score
    assert d1.score < 2 * d2.score
  end

  # -------------------------------------------------------
  # Length normalization
  # -------------------------------------------------------

  test "shorter document with equal term frequency ranks higher", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "long", %{body: "fox padding padding padding"})
    :ok = InvertedIndex.index(idx, "short", %{body: "fox"})

    results = InvertedIndex.search(idx, "fox")
    assert Enum.map(results, & &1.id) == ["short", "long"]
  end

  # -------------------------------------------------------
  # IDF weighting
  # -------------------------------------------------------

  test "rare terms outscore common terms", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "data data data analysis"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "data analysis report summary"})
    :ok = InvertedIndex.index(idx, "doc3", %{body: "report summary overview"})

    [rare] = InvertedIndex.search(idx, "overview")
    common = InvertedIndex.search(idx, "data") |> List.last()

    assert rare.score > common.score
  end

  # -------------------------------------------------------
  # Stop words
  # -------------------------------------------------------

  test "stop words are not searchable", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "the cat is on the mat"})

    assert InvertedIndex.search(idx, "the") == []
    assert InvertedIndex.search(idx, "is") == []
    assert length(InvertedIndex.search(idx, "cat")) == 1
  end

  test "custom stop words override the defaults", _ctx do
    {:ok, idx} = InvertedIndex.start_link(stop_words: MapSet.new(["foo", "bar"]))

    :ok = InvertedIndex.index(idx, "doc1", %{body: "foo baz bar qux"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "the quick brown"})

    assert InvertedIndex.search(idx, "foo") == []
    assert InvertedIndex.search(idx, "bar") == []
    assert length(InvertedIndex.search(idx, "the")) == 1
  end

  # -------------------------------------------------------
  # Field boosting
  # -------------------------------------------------------

  test "title boost makes a title match rank higher", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{title: "fox", body: "lazy"})
    :ok = InvertedIndex.index(idx, "doc2", %{title: "lazy", body: "fox"})

    results = InvertedIndex.search(idx, "fox", boosts: %{title: 5, body: 1})
    assert Enum.map(results, & &1.id) == ["doc1", "doc2"]
    assert hd(results).score > List.last(results).score
  end

  test "boosting a field raises the score for the same document", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{title: "fox", body: "animal"})
    :ok = InvertedIndex.index(idx, "doc2", %{title: "animals", body: "clever"})

    boosted = InvertedIndex.search(idx, "fox", boosts: %{title: 5, body: 1})
    unboosted = InvertedIndex.search(idx, "fox")

    b = Enum.find(boosted, &(&1.id == "doc1")).score
    u = Enum.find(unboosted, &(&1.id == "doc1")).score
    assert b > u
  end

  # -------------------------------------------------------
  # Limit
  # -------------------------------------------------------

  test "limit caps the number of returned results", %{idx: idx} do
    for i <- 1..20 do
      :ok = InvertedIndex.index(idx, "doc#{i}", %{body: "keyword variation#{i} extra text"})
    end

    assert length(InvertedIndex.search(idx, "keyword", limit: 5)) == 5
    assert length(InvertedIndex.search(idx, "keyword")) == 20
  end

  # -------------------------------------------------------
  # Removal and re-indexing
  # -------------------------------------------------------

  test "removed document no longer appears and stops contributing to counts", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "alpha beta gamma"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "beta gamma delta"})
    :ok = InvertedIndex.index(idx, "doc3", %{body: "gamma delta epsilon"})

    assert InvertedIndex.stats(idx).document_count == 3
    :ok = InvertedIndex.remove(idx, "doc2")
    assert InvertedIndex.stats(idx).document_count == 2

    beta = InvertedIndex.search(idx, "beta")
    assert length(beta) == 1
    assert hd(beta).id == "doc1"
  end

  test "removing non-existent doc does not raise", %{idx: idx} do
    assert :ok = InvertedIndex.remove(idx, "nonexistent")
  end

  test "re-indexing replaces previous content", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "apple banana cherry"})
    assert length(InvertedIndex.search(idx, "apple")) == 1

    :ok = InvertedIndex.index(idx, "doc1", %{body: "delta epsilon zeta"})
    assert InvertedIndex.search(idx, "apple") == []
    assert hd(InvertedIndex.search(idx, "delta")).id == "doc1"
    assert InvertedIndex.stats(idx).document_count == 1
  end

  # -------------------------------------------------------
  # Suggestion
  # -------------------------------------------------------

  test "suggest returns prefix matches sorted by document frequency", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "programming program problems"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "program productivity projects"})
    :ok = InvertedIndex.index(idx, "doc3", %{body: "testing productivity"})

    suggestions = InvertedIndex.suggest(idx, "pro")
    assert Enum.all?(suggestions, &String.starts_with?(&1, "pro"))
    top_two = Enum.take(suggestions, 2)
    assert "program" in top_two
    assert "productivity" in top_two
  end

  test "suggest respects limit, is case-insensitive, and defaults to 10", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "programming program problems"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "program productivity projects"})
    assert length(InvertedIndex.suggest(idx, "pro", 2)) == 2
    assert length(InvertedIndex.suggest(idx, "PRO")) > 0

    words = Enum.map_join(1..12, " ", fn i -> "pre#{i}" end)
    :ok = InvertedIndex.index(idx, "doc3", %{body: words})
    assert length(InvertedIndex.suggest(idx, "pre")) == 10
  end

  test "suggest returns empty list for non-matching prefix", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "alpha beta gamma"})
    assert InvertedIndex.suggest(idx, "xyz") == []
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "search on empty index returns empty list", %{idx: idx} do
    assert InvertedIndex.search(idx, "anything") == []
  end

  test "punctuation is stripped during tokenization", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "Hello, world! This is a test."})
    assert length(InvertedIndex.search(idx, "hello")) == 1
    assert length(InvertedIndex.search(idx, "world")) == 1
  end

  test "accepts :name option for registration" do
    {:ok, _pid} = InvertedIndex.start_link(name: :bm25_index)
    :ok = InvertedIndex.index(:bm25_index, "doc1", %{body: "hello world"})
    assert length(InvertedIndex.search(:bm25_index, "hello")) == 1
  end
end
