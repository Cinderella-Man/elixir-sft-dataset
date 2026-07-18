  test "search on empty index returns empty list", %{idx: idx} do
    assert InvertedIndex.search(idx, {:term, "anything"}) == []
    assert InvertedIndex.search(idx, {:phrase, "any thing"}) == []
  end