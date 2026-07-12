  test "exact matches outrank near-miss matches", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "color color")
    :ok = FuzzyIndex.index(idx, "doc2", "colour")

    results = FuzzyIndex.search(idx, "color")
    assert Enum.map(results, & &1.id) == ["doc1", "doc2"]

    # doc1: exact "color" (similarity 2) occurring twice → 2 * 2 = 4
    # doc2: near "colour" at distance 1 (similarity 1) occurring once → 1 * 1 = 1
    assert Enum.find(results, &(&1.id == "doc1")).score == 4
    assert Enum.find(results, &(&1.id == "doc2")).score == 1
  end