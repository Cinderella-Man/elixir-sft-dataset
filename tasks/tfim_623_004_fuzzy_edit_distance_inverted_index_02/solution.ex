  test "indexes documents and finds them by exact keyword", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "the quick brown fox")
    :ok = FuzzyIndex.index(idx, "doc2", "the lazy dog")

    results = FuzzyIndex.search(idx, "fox")
    assert length(results) == 1
    assert hd(results).id == "doc1"
  end