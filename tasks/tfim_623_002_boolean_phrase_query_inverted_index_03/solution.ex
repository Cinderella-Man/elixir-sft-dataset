  test "term query is case-insensitive", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "Quick Brown Fox"})
    assert InvertedIndex.search(idx, {:term, "FOX"}) == ["a"]
  end