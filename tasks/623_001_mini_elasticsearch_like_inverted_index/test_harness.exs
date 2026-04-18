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

    results = InvertedIndex.search(idx, "quick brown")
    ids = Enum.map(results, & &1.id)
    assert length(results) == 2
    assert "doc1" in ids
    assert "doc2" in ids
  end

  # -------------------------------------------------------
  # Stats
  # -------------------------------------------------------

  test "stats reflects document and term counts", %{idx: idx} do
    assert %{document_count: 0, term_count: 0} = InvertedIndex.stats(idx)

    :ok = InvertedIndex.index(idx, "doc1", %{body: "alpha beta gamma"})
    stats = InvertedIndex.stats(idx)
    assert stats.document_count == 1
    assert stats.term_count == 3

    :ok = InvertedIndex.index(idx, "doc2", %{body: "beta gamma delta"})
    stats = InvertedIndex.stats(idx)
    assert stats.document_count == 2
    assert stats.term_count == 4
  end

  # -------------------------------------------------------
  # TF-IDF scoring
  # -------------------------------------------------------

  test "document with higher term frequency ranks first", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "data data data analysis"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "data analysis report summary"})
    :ok = InvertedIndex.index(idx, "doc3", %{body: "report summary overview"})

    results = InvertedIndex.search(idx, "data")
    assert length(results) == 2
    assert hd(results).id == "doc1"
    assert hd(results).score > List.last(results).score
  end

  test "rare terms get higher IDF weight", %{idx: idx} do
    # "overview" appears in 1 doc, "data" in 2 — overview has higher IDF
    :ok = InvertedIndex.index(idx, "doc1", %{body: "data data data analysis"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "data analysis report summary"})
    :ok = InvertedIndex.index(idx, "doc3", %{body: "report summary overview"})

    [rare] = InvertedIndex.search(idx, "overview")
    [_top, common] = InvertedIndex.search(idx, "data")

    # rare term "overview" in single doc can outscore common term "data" in its weaker doc
    assert rare.score > common.score
  end

  # -------------------------------------------------------
  # Stop word removal
  # -------------------------------------------------------

  test "stop words are not searchable", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "the cat is on the mat"})

    assert InvertedIndex.search(idx, "the") == []
    assert InvertedIndex.search(idx, "is") == []
    assert InvertedIndex.search(idx, "on") == []

    assert length(InvertedIndex.search(idx, "cat")) == 1
  end

  test "document with only stop words is not searchable", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "stoponly", %{body: "the a an is are was"})

    assert InvertedIndex.search(idx, "the") == []
    assert InvertedIndex.search(idx, "is") == []
  end

  # -------------------------------------------------------
  # Custom stop words
  # -------------------------------------------------------

  test "custom stop words override the defaults", _ctx do
    {:ok, idx} = InvertedIndex.start_link(stop_words: MapSet.new(["foo", "bar"]))

    :ok = InvertedIndex.index(idx, "doc1", %{body: "foo baz bar qux"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "the quick brown"})

    # "foo" and "bar" are now stop words
    assert InvertedIndex.search(idx, "foo") == []
    assert InvertedIndex.search(idx, "bar") == []

    # "the" is NOT a stop word under the custom set, so it IS indexed
    assert length(InvertedIndex.search(idx, "the")) == 1
  end

  # -------------------------------------------------------
  # Field-level boosting
  # -------------------------------------------------------

  test "title boost makes title matches rank higher", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{title: "fox", body: "an animal that runs fast"})
    :ok = InvertedIndex.index(idx, "doc2", %{title: "animals", body: "fox quick clever"})

    boosted = InvertedIndex.search(idx, "fox", boosts: %{title: 5, body: 1})
    assert length(boosted) == 2
    assert hd(boosted).id == "doc1"
  end

  test "boosted score is higher than default score for the same doc", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{title: "fox", body: "an animal"})
    :ok = InvertedIndex.index(idx, "doc2", %{title: "animals", body: "quick clever"})

    boosted = InvertedIndex.search(idx, "fox", boosts: %{title: 5, body: 1})
    unboosted = InvertedIndex.search(idx, "fox")

    doc1_boosted = Enum.find(boosted, &(&1.id == "doc1")).score
    doc1_unboosted = Enum.find(unboosted, &(&1.id == "doc1")).score

    assert doc1_boosted > doc1_unboosted
  end

  # -------------------------------------------------------
  # Multi-field scoring without boosts
  # -------------------------------------------------------

  test "term in multiple fields scores higher than in one field", %{idx: idx} do
    :ok =
      InvertedIndex.index(idx, "doc1", %{title: "python guide", body: "learn python programming"})

    :ok = InvertedIndex.index(idx, "doc2", %{title: "java guide", body: "learn python basics"})

    results = InvertedIndex.search(idx, "python")
    assert length(results) == 2
    assert hd(results).id == "doc1"
  end

  # -------------------------------------------------------
  # Search limit
  # -------------------------------------------------------

  test "limit caps number of returned results", %{idx: idx} do
    for i <- 1..20 do
      :ok = InvertedIndex.index(idx, "doc#{i}", %{body: "keyword variation#{i} extra text"})
    end

    limited = InvertedIndex.search(idx, "keyword", limit: 5)
    assert length(limited) == 5

    unlimited = InvertedIndex.search(idx, "keyword")
    assert length(unlimited) == 20
  end

  # -------------------------------------------------------
  # Stemming
  # -------------------------------------------------------

  test "stemmed search matches morphological variants", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "running jumps quickly"}, stem: true)
    :ok = InvertedIndex.index(idx, "doc2", %{body: "jumped runner slowly"}, stem: true)
    :ok = InvertedIndex.index(idx, "doc3", %{body: "unrelated content here"}, stem: true)

    run_results = InvertedIndex.search(idx, "running", stem: true)
    assert length(run_results) >= 2

    jump_results = InvertedIndex.search(idx, "jumped", stem: true)
    assert length(jump_results) >= 2
  end

  test "unstemmed query does not match stemmed index", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "running jumps"}, stem: true)

    # Stored as "run", "jump"; query "running" not stemmed → no match
    results = InvertedIndex.search(idx, "running")
    assert results == []
  end

  # -------------------------------------------------------
  # Document removal
  # -------------------------------------------------------

  test "removed document no longer appears in results", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "alpha beta gamma"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "beta gamma delta"})
    :ok = InvertedIndex.index(idx, "doc3", %{body: "gamma delta epsilon"})

    assert InvertedIndex.stats(idx).document_count == 3

    :ok = InvertedIndex.remove(idx, "doc2")

    assert InvertedIndex.stats(idx).document_count == 2

    beta = InvertedIndex.search(idx, "beta")
    assert length(beta) == 1
    assert hd(beta).id == "doc1"

    delta = InvertedIndex.search(idx, "delta")
    assert length(delta) == 1
    assert hd(delta).id == "doc3"
  end

  test "removing non-existent doc does not raise", %{idx: idx} do
    assert :ok = InvertedIndex.remove(idx, "nonexistent")
  end

  # -------------------------------------------------------
  # Document re-indexing (update)
  # -------------------------------------------------------

  test "re-indexing replaces previous content", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "apple banana cherry"})
    assert length(InvertedIndex.search(idx, "apple")) == 1

    :ok = InvertedIndex.index(idx, "doc1", %{body: "delta epsilon zeta"})

    assert InvertedIndex.search(idx, "apple") == []
    assert length(InvertedIndex.search(idx, "delta")) == 1
    assert hd(InvertedIndex.search(idx, "delta")).id == "doc1"
    assert InvertedIndex.stats(idx).document_count == 1
  end

  # -------------------------------------------------------
  # Prefix suggestion
  # -------------------------------------------------------

  test "suggest returns terms matching the prefix sorted by doc frequency", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "programming program problems"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "program productivity projects"})
    :ok = InvertedIndex.index(idx, "doc3", %{body: "testing productivity"})

    suggestions = InvertedIndex.suggest(idx, "pro")
    assert length(suggestions) > 0
    assert Enum.all?(suggestions, &String.starts_with?(&1, "pro"))

    # "program" in 2 docs, "productivity" in 2 docs → both should come before
    # "programming", "problems", "projects" (each in 1 doc)
    top_two = Enum.take(suggestions, 2)
    assert "program" in top_two
    assert "productivity" in top_two
  end

  test "suggest respects limit", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "programming program problems"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "program productivity projects"})

    limited = InvertedIndex.suggest(idx, "pro", 2)
    assert length(limited) == 2
  end

  test "suggest returns empty list for non-matching prefix", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "alpha beta gamma"})
    assert InvertedIndex.suggest(idx, "xyz") == []
  end

  test "suggest is case-insensitive", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "programming program"})

    assert length(InvertedIndex.suggest(idx, "PRO")) > 0
  end

  # -------------------------------------------------------
  # Empty index edge cases
  # -------------------------------------------------------

  test "search on empty index returns empty list", %{idx: idx} do
    assert InvertedIndex.search(idx, "anything") == []
  end

  test "suggest on empty index returns empty list", %{idx: idx} do
    assert InvertedIndex.suggest(idx, "abc") == []
  end

  # -------------------------------------------------------
  # Punctuation and special characters
  # -------------------------------------------------------

  test "punctuation is stripped during tokenization", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "Hello, world! This is a test."})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "hello-world test-driven development"})

    assert length(InvertedIndex.search(idx, "hello")) >= 1
    assert length(InvertedIndex.search(idx, "world")) >= 1
    assert length(InvertedIndex.search(idx, "test")) >= 1
  end

  # -------------------------------------------------------
  # Named process registration
  # -------------------------------------------------------

  test "accepts :name option for registration" do
    {:ok, _pid} = InvertedIndex.start_link(name: :my_index)

    :ok = InvertedIndex.index(:my_index, "doc1", %{body: "hello world"})
    results = InvertedIndex.search(:my_index, "hello")
    assert length(results) == 1
  end
end
