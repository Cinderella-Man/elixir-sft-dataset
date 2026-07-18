  test "removing a document decrements per-term document frequency for idf", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "beta alpha"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "gamma delta"})
    :ok = InvertedIndex.index(idx, "doc3", %{body: "beta zeta"})

    :ok = InvertedIndex.remove(idx, "doc3")

    # "beta" is now in exactly 1 of 2 documents: tf = 1/2, idf = log(2/1)
    [result] = InvertedIndex.search(idx, "beta")
    assert result.id == "doc1"
    assert_in_delta result.score, :math.log(2) / 2, 1.0e-9

    # "zeta" left with doc3; the vocabulary is alpha, beta, gamma, delta
    assert InvertedIndex.stats(idx).term_count == 4
    assert InvertedIndex.suggest(idx, "zeta") == []
  end