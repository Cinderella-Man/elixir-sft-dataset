  test "limit keeps the highest scoring results, not arbitrary ones", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "low", "keyword")
    :ok = FuzzyIndex.index(idx, "mid", "keyword keyword")
    :ok = FuzzyIndex.index(idx, "high", "keyword keyword keyword")

    assert Enum.map(FuzzyIndex.search(idx, "keyword", limit: 1), & &1.id) == ["high"]
    assert Enum.map(FuzzyIndex.search(idx, "keyword", limit: 2), & &1.id) == ["high", "mid"]
  end