  test "repeated query terms are scored once, not once per occurrence", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "fox fox cat"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "dog bird"})

    [single] = InvertedIndex.search(idx, "fox")
    [repeated] = InvertedIndex.search(idx, "fox fox fox")

    assert repeated.id == single.id
    assert_in_delta repeated.score, single.score, 1.0e-9
  end