  test "multi-term search returns all matching documents", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "the quick brown fox"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "the quick brown cat"})
    :ok = InvertedIndex.index(idx, "doc3", %{body: "a slow green turtle"})

    ids = InvertedIndex.search(idx, "quick brown") |> Enum.map(& &1.id)
    assert length(ids) == 2
    assert "doc1" in ids
    assert "doc2" in ids
  end