  test "term query with multi-token word uses only the first token", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "quick brown fox"})
    :ok = InvertedIndex.index(idx, "b", %{body: "quick green turtle"})
    :ok = InvertedIndex.index(idx, "c", %{body: "slow brown bear"})

    # tokenizes to ["quick", "brown"]; only "quick" is used
    assert InvertedIndex.search(idx, {:term, "quick brown"}) == ["a", "b"]
    # punctuation-separated form tokenizes the same way
    assert InvertedIndex.search(idx, {:term, "quick, brown!"}) == ["a", "b"]
  end