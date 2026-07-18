  test "removed document drops its exclusive terms from the vocabulary", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "quick brown fox"})
    :ok = InvertedIndex.index(idx, "b", %{body: "quick brown cat"})
    assert InvertedIndex.stats(idx).term_count == 4

    :ok = InvertedIndex.remove(idx, "a")

    assert InvertedIndex.search(idx, {:term, "fox"}) == []
    assert InvertedIndex.search(idx, {:phrase, "brown fox"}) == []
    assert InvertedIndex.suggest(idx, "fo") == []
    assert InvertedIndex.stats(idx).term_count == 3
  end