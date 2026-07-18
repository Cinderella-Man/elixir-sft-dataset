  test "indexing without the stem option stores unstemmed tokens", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "walking"})

    # stemming is controlled per-call via opts[:stem]; absent means off, so the
    # stored term is the literal token "walking", not the stem "walk"
    assert [%{id: "doc1"}] = InvertedIndex.search(idx, "walking")
    assert InvertedIndex.search(idx, "walk") == []
  end