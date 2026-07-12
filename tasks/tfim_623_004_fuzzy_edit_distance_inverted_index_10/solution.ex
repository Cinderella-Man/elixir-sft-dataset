  test "punctuation is stripped and produces no empty terms", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "Hello, world!")

    # splitting on ~r/[^a-z0-9]+/ yields exactly ["hello", "world"]
    assert FuzzyIndex.stats(idx).term_count == 2
    assert length(FuzzyIndex.search(idx, "hello")) == 1
    assert length(FuzzyIndex.search(idx, "world")) == 1
  end