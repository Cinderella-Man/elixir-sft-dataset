  test "exact BM25 score when boosts weight both f(t,d) and avgdl", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{title: "fox", body: "fox cat"})
    :ok = InvertedIndex.index(idx, "doc2", %{title: "dog", body: "bird"})

    # boosts %{title: 3}: |d1| = 1*3 + 2*1 = 5, |d2| = 1*3 + 1*1 = 4, avgdl = 4.5
    # f(fox,doc1) = 1*3 + 1*1 = 4 ; N=2, df(fox)=1 -> IDF = ln(1 + 1.5/1.5) = ln 2
    [result] = InvertedIndex.search(idx, "fox", boosts: %{title: 3})
    assert result.id == "doc1"

    ratio = 5.0 / 4.5
    denom = 4.0 + 1.2 * (1 - 0.75 + 0.75 * ratio)
    expected = :math.log(2) * (4.0 * 2.2) / denom
    assert_in_delta result.score, expected, 1.0e-9
  end