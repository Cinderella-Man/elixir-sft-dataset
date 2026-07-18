  test "terms_like excludes terms beyond the distance and lowercases its input", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "color")
    :ok = FuzzyIndex.index(idx, "doc2", "colour")
    :ok = FuzzyIndex.index(idx, "doc3", "cold")

    # color=0, colour=1, cold=2 (excluded at max 1); input "COLOR" is lowercased
    assert FuzzyIndex.terms_like(idx, "COLOR", 1) == ["color", "colour"]
  end