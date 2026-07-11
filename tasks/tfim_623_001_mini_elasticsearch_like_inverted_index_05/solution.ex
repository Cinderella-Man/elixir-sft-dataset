  test "document with higher term frequency ranks first", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "data data data analysis"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "data analysis report summary"})
    :ok = InvertedIndex.index(idx, "doc3", %{body: "report summary overview"})

    results = InvertedIndex.search(idx, "data")
    assert length(results) == 2
    assert hd(results).id == "doc1"
    assert hd(results).score > List.last(results).score
  end