  test "terms_like defaults to max distance 1", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "banana")

    assert FuzzyIndex.terms_like(idx, "banan") == ["banana"]
    assert FuzzyIndex.terms_like(idx, "bana") == []
  end