  test "empty and matches all, empty or matches none", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "quick brown fox"})
    :ok = InvertedIndex.index(idx, "b", %{body: "slow turtle"})

    assert InvertedIndex.search(idx, {:and, []}) == ["a", "b"]
    assert InvertedIndex.search(idx, {:or, []}) == []
  end