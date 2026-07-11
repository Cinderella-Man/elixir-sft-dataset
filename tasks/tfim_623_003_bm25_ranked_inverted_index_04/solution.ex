  test "stats reflects document and term counts", %{idx: idx} do
    assert %{document_count: 0, term_count: 0} = InvertedIndex.stats(idx)

    :ok = InvertedIndex.index(idx, "doc1", %{body: "alpha beta gamma"})
    assert InvertedIndex.stats(idx).document_count == 1
    assert InvertedIndex.stats(idx).term_count == 3

    :ok = InvertedIndex.index(idx, "doc2", %{body: "beta gamma delta"})
    assert InvertedIndex.stats(idx).document_count == 2
    assert InvertedIndex.stats(idx).term_count == 4
  end