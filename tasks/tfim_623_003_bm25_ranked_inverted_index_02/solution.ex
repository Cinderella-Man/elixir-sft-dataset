  test "indexes documents and finds them by keyword", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "the quick brown fox jumps over the lazy dog"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "the quick brown cat sits on the mat"})
    :ok = InvertedIndex.index(idx, "doc3", %{body: "a slow green turtle crosses the road"})

    results = InvertedIndex.search(idx, "fox")
    assert length(results) == 1
    assert hd(results).id == "doc1"
  end