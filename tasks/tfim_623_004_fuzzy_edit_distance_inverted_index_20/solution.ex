  test "repeated query terms do not multiply a document's score", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "data data")

    [once] = FuzzyIndex.search(idx, "data")
    [thrice] = FuzzyIndex.search(idx, "data data data")

    # exact "data" (similarity 2) occurring twice → 2 * 2 = 4, counted a single time
    assert once.score == 4
    assert thrice.score == 4
  end