  test "max_distance option widens or narrows fuzzy matching", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "banana")

    # "banan" is distance 1 from "banana" → matches by default
    assert Enum.map(FuzzyIndex.search(idx, "banan"), & &1.id) == ["doc1"]

    # "bana" is distance 2 from "banana" → no match at the default max_distance of 1
    assert FuzzyIndex.search(idx, "bana") == []

    # ... but matches when max_distance is raised to 2
    assert Enum.map(FuzzyIndex.search(idx, "bana", max_distance: 2), & &1.id) == ["doc1"]
  end