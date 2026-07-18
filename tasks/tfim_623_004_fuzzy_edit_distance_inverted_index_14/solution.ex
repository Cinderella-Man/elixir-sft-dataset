  test "removed document no longer appears and vocabulary shrinks", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "alpha beta")
    :ok = FuzzyIndex.index(idx, "doc2", "beta gamma")
    :ok = FuzzyIndex.index(idx, "doc3", "gamma delta")

    assert FuzzyIndex.stats(idx).document_count == 3

    :ok = FuzzyIndex.remove(idx, "doc2")

    assert FuzzyIndex.stats(idx).document_count == 2

    # "beta" now only in doc1, "gamma" now only in doc3
    assert Enum.map(FuzzyIndex.search(idx, "beta"), & &1.id) == ["doc1"]
    assert Enum.map(FuzzyIndex.search(idx, "gamma"), & &1.id) == ["doc3"]

    # vocabulary is alpha, beta, gamma, delta
    assert FuzzyIndex.stats(idx).term_count == 4
  end