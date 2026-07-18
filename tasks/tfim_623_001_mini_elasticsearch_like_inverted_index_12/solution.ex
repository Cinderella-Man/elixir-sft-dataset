  test "term in multiple fields scores higher than in one field", %{idx: idx} do
    :ok =
      InvertedIndex.index(idx, "doc1", %{title: "python guide", body: "learn python programming"})

    :ok = InvertedIndex.index(idx, "doc2", %{title: "java guide", body: "learn python basics"})
    # a third doc without the term keeps idf > 0, so the field-sum comparison is real
    :ok = InvertedIndex.index(idx, "doc3", %{title: "ruby guide", body: "learn ruby basics"})

    results = InvertedIndex.search(idx, "python")
    assert Enum.map(results, & &1.id) == ["doc1", "doc2"]
    assert hd(results).score > List.last(results).score
  end