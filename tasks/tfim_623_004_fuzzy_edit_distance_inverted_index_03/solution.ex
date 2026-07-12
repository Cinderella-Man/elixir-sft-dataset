  test "a typo within edit distance 1 still matches by default", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "quick brown fox")
    :ok = FuzzyIndex.index(idx, "doc2", "slow green turtle")

    # "quik" is edit distance 1 from "quick" and far from every other term
    results = FuzzyIndex.search(idx, "quik")
    assert Enum.map(results, & &1.id) == ["doc1"]
  end