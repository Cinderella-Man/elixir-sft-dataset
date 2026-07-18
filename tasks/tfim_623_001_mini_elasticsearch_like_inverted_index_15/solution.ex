  test "unstemmed query does not match stemmed index", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "running jumps"}, stem: true)

    # Stored as "run", "jump"; query "running" not stemmed → no match
    results = InvertedIndex.search(idx, "running")
    assert results == []
  end