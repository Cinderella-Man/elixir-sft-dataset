  test "custom k1 and b change the score as specified", _ctx do
    {:ok, idx} = InvertedIndex.start_link(k1: 2.0, b: 0.0)
    :ok = InvertedIndex.index(idx, "doc1", %{body: "fox fox cat"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "dog bird"})

    # b=0 removes length normalization: denom = f + k1 = 2 + 2 = 4 ; numer = f*(k1+1) = 6
    # IDF = ln 2 ; score = ln 2 * 6/4 = ln 2 * 1.5
    [result] = InvertedIndex.search(idx, "fox")
    assert_in_delta result.score, :math.log(2) * 1.5, 1.0e-9
  end