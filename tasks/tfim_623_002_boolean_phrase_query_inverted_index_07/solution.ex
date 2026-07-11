  test "not excludes matching documents", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "quick brown fox"})
    :ok = InvertedIndex.index(idx, "b", %{body: "quick brown cat"})
    :ok = InvertedIndex.index(idx, "c", %{body: "slow green turtle"})

    assert InvertedIndex.search(idx, {:not, {:term, "fox"}}) == ["b", "c"]
  end