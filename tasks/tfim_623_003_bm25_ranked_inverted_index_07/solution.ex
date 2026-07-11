  test "term frequency saturates rather than scaling linearly", %{idx: idx} do
    # both docs have length 4, so length normalization is identical
    :ok = InvertedIndex.index(idx, "doc1", %{body: "fox fox fox fox"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "fox cat dog bird"})

    results = InvertedIndex.search(idx, "fox")
    d1 = Enum.find(results, &(&1.id == "doc1"))
    d2 = Enum.find(results, &(&1.id == "doc2"))

    # 4x the raw term frequency must NOT give ~4x the score (saturation)
    assert d1.score > d2.score
    assert d1.score < 2 * d2.score
  end