  test "stop words are not searchable", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "the cat is on the mat"})

    assert InvertedIndex.search(idx, "the") == []
    assert InvertedIndex.search(idx, "is") == []
    assert length(InvertedIndex.search(idx, "cat")) == 1
  end