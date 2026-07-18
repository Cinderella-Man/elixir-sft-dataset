  test "leading and trailing punctuation adds no tokens or terms", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "Hello, world!"})

    # splitting on ~r/[^a-z0-9]+/ yields exactly ["hello", "world"]
    assert InvertedIndex.stats(idx).term_count == 2
  end