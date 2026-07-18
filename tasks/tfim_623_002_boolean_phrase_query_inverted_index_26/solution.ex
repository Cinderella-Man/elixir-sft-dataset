  test "punctuation is stripped during tokenization", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "Hello, world! This is a test."})
    assert InvertedIndex.search(idx, {:term, "hello"}) == ["a"]
    assert InvertedIndex.search(idx, {:term, "world"}) == ["a"]
    assert InvertedIndex.search(idx, {:phrase, "hello world"}) == ["a"]
  end