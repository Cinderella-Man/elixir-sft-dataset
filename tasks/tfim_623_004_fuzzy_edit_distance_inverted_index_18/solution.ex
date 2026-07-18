  test "search on an empty index returns an empty list", %{idx: idx} do
    assert FuzzyIndex.search(idx, "anything") == []
  end