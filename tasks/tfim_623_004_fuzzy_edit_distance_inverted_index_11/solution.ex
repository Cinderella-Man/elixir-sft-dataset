  test "stats reflects document and vocabulary counts", %{idx: idx} do
    assert %{document_count: 0, term_count: 0} = FuzzyIndex.stats(idx)

    :ok = FuzzyIndex.index(idx, "doc1", "alpha beta gamma")
    stats = FuzzyIndex.stats(idx)
    assert stats.document_count == 1
    assert stats.term_count == 3

    :ok = FuzzyIndex.index(idx, "doc2", "beta gamma delta")
    stats = FuzzyIndex.stats(idx)
    assert stats.document_count == 2
    assert stats.term_count == 4
  end