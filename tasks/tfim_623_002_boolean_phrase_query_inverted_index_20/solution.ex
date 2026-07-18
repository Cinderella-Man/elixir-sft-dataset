  test "re-indexing replaces previous content", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "apple banana cherry"})
    assert InvertedIndex.search(idx, {:term, "apple"}) == ["a"]

    :ok = InvertedIndex.index(idx, "a", %{body: "delta epsilon zeta"})
    assert InvertedIndex.search(idx, {:term, "apple"}) == []
    assert InvertedIndex.search(idx, {:term, "delta"}) == ["a"]
    assert InvertedIndex.stats(idx).document_count == 1
  end