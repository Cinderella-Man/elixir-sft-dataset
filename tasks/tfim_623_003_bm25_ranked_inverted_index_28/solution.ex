  test "mixed-case occurrences collapse into one term for scoring", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "Fox FOX fOx"})

    # N=1, df(fox)=1 -> IDF = ln(1 + 0.5/1.5) ; f=3, |d|=3, avgdl=3 -> denom = 3 + 1.2
    [result] = InvertedIndex.search(idx, "FoX")
    assert result.id == "doc1"
    assert InvertedIndex.stats(idx).term_count == 1

    expected = :math.log(1 + 0.5 / 1.5) * (3.0 * 2.2) / 4.2
    assert_in_delta result.score, expected, 1.0e-9
  end