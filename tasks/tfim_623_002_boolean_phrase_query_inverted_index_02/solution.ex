  test "term query finds documents containing the token", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "the quick brown fox"})
    :ok = InvertedIndex.index(idx, "b", %{body: "the quick brown cat"})
    :ok = InvertedIndex.index(idx, "c", %{body: "a slow green turtle"})

    assert InvertedIndex.search(idx, {:term, "fox"}) == ["a"]
    assert InvertedIndex.search(idx, {:term, "quick"}) == ["a", "b"]
  end