  test "and returns intersection", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "quick brown fox"})
    :ok = InvertedIndex.index(idx, "b", %{body: "quick brown cat"})
    :ok = InvertedIndex.index(idx, "c", %{body: "slow green turtle"})

    result = InvertedIndex.search(idx, {:and, [{:term, "quick"}, {:term, "brown"}]})
    assert result == ["a", "b"]

    result2 = InvertedIndex.search(idx, {:and, [{:term, "quick"}, {:term, "fox"}]})
    assert result2 == ["a"]
  end