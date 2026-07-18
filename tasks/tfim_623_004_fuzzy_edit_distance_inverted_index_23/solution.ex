  test "every documented default stop word is dropped during tokenization", %{idx: idx} do
    text =
      "the a an is are was were in on at to of and or it this that for with as by " <>
        "not be has had have do does did but if from marker"

    :ok = FuzzyIndex.index(idx, "doc1", text)

    assert FuzzyIndex.stats(idx).term_count == 1
    assert FuzzyIndex.terms_like(idx, "marker", 0) == ["marker"]
  end