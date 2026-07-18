  test "stop words in a phrase are dropped before matching", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "quick brown fox"})
    # "the" is a stop word: phrase tokenizes to ["brown", "fox"] which is consecutive
    assert InvertedIndex.search(idx, {:phrase, "brown the fox"}) == ["a"]
  end