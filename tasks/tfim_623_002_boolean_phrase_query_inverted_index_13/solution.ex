  test "phrase must lie within a single field", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "d", %{title: "quick", body: "brown cat"})

    # "quick" is in title, "brown" is in body -> not a single-field phrase
    assert InvertedIndex.search(idx, {:phrase, "quick brown"}) == []
    # but each term individually is findable in some field
    assert InvertedIndex.search(idx, {:term, "quick"}) == ["d"]
  end