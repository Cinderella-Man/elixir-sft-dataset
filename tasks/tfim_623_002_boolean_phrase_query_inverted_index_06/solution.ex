  test "or returns union", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "quick brown fox"})
    :ok = InvertedIndex.index(idx, "b", %{body: "quick brown cat"})
    :ok = InvertedIndex.index(idx, "c", %{body: "slow green turtle"})

    result = InvertedIndex.search(idx, {:or, [{:term, "fox"}, {:term, "turtle"}]})
    assert result == ["a", "c"]
  end