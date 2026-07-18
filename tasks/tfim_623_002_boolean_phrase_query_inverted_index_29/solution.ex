  test "phrase of only stop words matches no documents", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "the quick brown fox"})
    :ok = InvertedIndex.index(idx, "b", %{body: "is on at the of"})

    assert InvertedIndex.search(idx, {:phrase, "the is of"}) == []
    assert InvertedIndex.search(idx, {:phrase, "!!! ,,,"}) == []
    assert InvertedIndex.search(idx, {:phrase, ""}) == []
  end