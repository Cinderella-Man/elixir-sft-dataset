  test "re-indexing replaces previous content", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "apple banana")
    assert length(FuzzyIndex.search(idx, "apple")) == 1

    :ok = FuzzyIndex.index(idx, "doc1", "delta epsilon")

    assert FuzzyIndex.search(idx, "apple") == []
    assert Enum.map(FuzzyIndex.search(idx, "delta"), & &1.id) == ["doc1"]
    assert FuzzyIndex.stats(idx).document_count == 1
    assert FuzzyIndex.stats(idx).term_count == 2
  end