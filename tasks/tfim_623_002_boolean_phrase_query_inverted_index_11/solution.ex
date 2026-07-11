  test "phrase matches consecutive terms", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "the quick brown fox"})
    :ok = InvertedIndex.index(idx, "b", %{body: "the quick brown cat"})

    assert InvertedIndex.search(idx, {:phrase, "quick brown"}) == ["a", "b"]
    assert InvertedIndex.search(idx, {:phrase, "brown fox"}) == ["a"]
  end