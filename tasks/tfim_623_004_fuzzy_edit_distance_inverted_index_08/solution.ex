  test "stop words are not searchable", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "the cat sat")

    assert FuzzyIndex.search(idx, "the") == []
    assert length(FuzzyIndex.search(idx, "cat")) == 1
  end