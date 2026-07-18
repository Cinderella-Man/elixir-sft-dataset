  test "phrase does not match non-consecutive terms", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "the quick brown fox"})
    # "quick" and "fox" both appear but are not adjacent
    assert InvertedIndex.search(idx, {:phrase, "quick fox"}) == []
  end