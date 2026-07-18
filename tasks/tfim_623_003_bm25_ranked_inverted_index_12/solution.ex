  test "title boost makes a title match rank higher", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{title: "fox", body: "lazy"})
    :ok = InvertedIndex.index(idx, "doc2", %{title: "lazy", body: "fox"})

    results = InvertedIndex.search(idx, "fox", boosts: %{title: 5, body: 1})
    assert Enum.map(results, & &1.id) == ["doc1", "doc2"]
    assert hd(results).score > List.last(results).score
  end