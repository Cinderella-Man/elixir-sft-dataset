  test "punctuation is stripped during tokenization", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "Hello, world! This is a test."})
    assert length(InvertedIndex.search(idx, "hello")) == 1
    assert length(InvertedIndex.search(idx, "world")) == 1
  end