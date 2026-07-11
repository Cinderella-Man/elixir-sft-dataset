  test "title boost makes title matches rank higher", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{title: "fox", body: "an animal that runs fast"})
    :ok = InvertedIndex.index(idx, "doc2", %{title: "animals", body: "fox quick clever"})
    # a third doc without the term keeps idf = log(3/2) > 0, so the scores are
    # real numbers — not an all-zero tie ranked by map-order accident
    :ok = InvertedIndex.index(idx, "doc3", %{title: "birds", body: "sparrow feathers sky"})

    boosted = InvertedIndex.search(idx, "fox", boosts: %{title: 5, body: 1})
    assert Enum.map(boosted, & &1.id) == ["doc1", "doc2"]
    assert hd(boosted).score > List.last(boosted).score
  end