  test "punctuation is stripped during tokenization", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "Hello, world! This is a test."})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "hello-world test-driven development"})

    assert length(InvertedIndex.search(idx, "hello")) >= 1
    assert length(InvertedIndex.search(idx, "world")) >= 1
    assert length(InvertedIndex.search(idx, "test")) >= 1
  end