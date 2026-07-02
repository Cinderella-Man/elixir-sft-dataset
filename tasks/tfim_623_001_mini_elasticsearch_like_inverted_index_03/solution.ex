  test "multi-term search returns all matching documents", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "the quick brown fox"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "the quick brown cat"})
    :ok = InvertedIndex.index(idx, "doc3", %{body: "a slow green turtle"})

    results = InvertedIndex.search(idx, "quick brown")
    ids = Enum.map(results, & &1.id)
    assert length(results) == 2
    assert "doc1" in ids
    assert "doc2" in ids
  end