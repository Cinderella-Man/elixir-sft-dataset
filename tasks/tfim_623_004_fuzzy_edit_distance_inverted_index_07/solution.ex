  test "multiple query terms sum their contributions", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "quick brown fox")

    [result] = FuzzyIndex.search(idx, "quick fox")
    assert result.id == "doc1"
    # each exact term contributes similarity 2 * count 1; 2 + 2 = 4
    assert result.score == 4
  end