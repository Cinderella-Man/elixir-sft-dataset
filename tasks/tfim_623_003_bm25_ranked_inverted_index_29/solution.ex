  test "removal purges the removed document's exclusive terms from the vocabulary", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "alpha beta"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "beta gamma"})
    assert InvertedIndex.stats(idx).term_count == 3

    :ok = InvertedIndex.remove(idx, "doc1")

    assert InvertedIndex.stats(idx).term_count == 2
    assert InvertedIndex.suggest(idx, "alpha") == []
    assert InvertedIndex.search(idx, "alpha") == []
    assert Enum.map(InvertedIndex.search(idx, "beta"), & &1.id) == ["doc2"]
  end