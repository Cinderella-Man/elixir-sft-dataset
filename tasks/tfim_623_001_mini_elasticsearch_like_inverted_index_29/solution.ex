  test "unlisted field boost defaults to exactly 1 in tf-idf scoring", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "fox runs fast"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "cat naps quietly"})

    # tf = 1/3, idf = log(2/1); :body is not listed in boosts so its boost is 1
    [result] = InvertedIndex.search(idx, "fox", boosts: %{title: 3})
    assert result.id == "doc1"
    assert_in_delta result.score, :math.log(2) / 3, 1.0e-9
  end