  test "rare terms get higher IDF weight", %{idx: idx} do
    # "overview" appears in 1 doc, "data" in 2 — overview has higher IDF
    :ok = InvertedIndex.index(idx, "doc1", %{body: "data data data analysis"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "data analysis report summary"})
    :ok = InvertedIndex.index(idx, "doc3", %{body: "report summary overview"})

    [rare] = InvertedIndex.search(idx, "overview")
    [_top, common] = InvertedIndex.search(idx, "data")

    # rare term "overview" in single doc can outscore common term "data" in its weaker doc
    assert rare.score > common.score
  end