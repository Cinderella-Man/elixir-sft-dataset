  test "removal lowers N so the IDF of a surviving term changes exactly", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "fox"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "cat"})
    :ok = InvertedIndex.index(idx, "doc3", %{body: "dog"})

    [before] = InvertedIndex.search(idx, "fox")
    assert_in_delta before.score, :math.log(1 + 2.5 / 1.5) * 2.2 / 2.2, 1.0e-9

    :ok = InvertedIndex.remove(idx, "doc3")

    # N=2, df(fox)=1 -> IDF = ln 2 ; |d|=1, avgdl=1 -> denom = 1 + 1.2 = 2.2, numer = 2.2
    [result] = InvertedIndex.search(idx, "fox")
    assert result.id == "doc1"
    assert_in_delta result.score, :math.log(2), 1.0e-9
  end