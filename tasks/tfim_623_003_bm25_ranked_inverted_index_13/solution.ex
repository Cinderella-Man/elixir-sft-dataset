  test "boosting a field raises the score for the same document", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{title: "fox", body: "animal"})
    :ok = InvertedIndex.index(idx, "doc2", %{title: "animals", body: "clever"})

    boosted = InvertedIndex.search(idx, "fox", boosts: %{title: 5, body: 1})
    unboosted = InvertedIndex.search(idx, "fox")

    b = Enum.find(boosted, &(&1.id == "doc1")).score
    u = Enum.find(unboosted, &(&1.id == "doc1")).score
    assert b > u
  end