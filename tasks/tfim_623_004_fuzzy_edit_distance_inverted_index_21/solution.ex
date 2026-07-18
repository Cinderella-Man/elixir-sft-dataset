  test "contribution takes the max over matching terms rather than summing them", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "color colour")

    [result] = FuzzyIndex.search(idx, "color")

    # exact "color" → 2 * 1 = 2 ; near "colour" → 1 * 1 = 1 ; max is 2, not the sum 3
    assert result.score == 2
  end