  test "suggest on empty index returns empty list", %{idx: idx} do
    assert InvertedIndex.suggest(idx, "abc") == []
  end