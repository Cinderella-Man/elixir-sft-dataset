  test "boosted score is higher than default score for the same doc", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{title: "fox", body: "an animal"})
    :ok = InvertedIndex.index(idx, "doc2", %{title: "animals", body: "quick clever"})

    boosted = InvertedIndex.search(idx, "fox", boosts: %{title: 5, body: 1})
    unboosted = InvertedIndex.search(idx, "fox")

    doc1_boosted = Enum.find(boosted, &(&1.id == "doc1")).score
    doc1_unboosted = Enum.find(unboosted, &(&1.id == "doc1")).score

    assert doc1_boosted > doc1_unboosted
  end