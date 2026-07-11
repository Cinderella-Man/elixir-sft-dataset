  test "term query for a stop word matches nothing", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "the cat on the mat"})
    assert InvertedIndex.search(idx, {:term, "the"}) == []
    assert InvertedIndex.search(idx, {:term, "cat"}) == ["a"]
  end