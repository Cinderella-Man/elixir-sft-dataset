  test "higher term frequency yields a higher score", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "data data data")
    :ok = FuzzyIndex.index(idx, "doc2", "data")

    results = FuzzyIndex.search(idx, "data")
    assert Enum.map(results, & &1.id) == ["doc1", "doc2"]
    # doc1: similarity 2 * count 3 = 6 ; doc2: similarity 2 * count 1 = 2
    assert Enum.find(results, &(&1.id == "doc1")).score == 6
    assert Enum.find(results, &(&1.id == "doc2")).score == 2
  end