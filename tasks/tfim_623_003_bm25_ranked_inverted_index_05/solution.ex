  test "exact BM25 score with default k1 and b", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "fox fox cat"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "dog bird"})

    # N=2, df(fox)=1 -> IDF = ln(1 + 1.5/1.5) = ln 2
    # f=2, |d|=3, avgdl=2.5, k1=1.2, b=0.75
    # denom = 2 + 1.2*(1 - 0.75 + 0.75*3/2.5) = 3.38 ; numer = 2*2.2 = 4.4
    # score = ln 2 * 4.4/3.38
    [result] = InvertedIndex.search(idx, "fox")
    assert result.id == "doc1"
    expected = :math.log(2) * 4.4 / 3.38
    assert_in_delta result.score, expected, 1.0e-9
  end