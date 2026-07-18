  test "uppercase text and uppercase queries match each other", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "HELLO World")

    assert Enum.map(FuzzyIndex.search(idx, "HELLO"), & &1.id) == ["doc1"]
    assert Enum.map(FuzzyIndex.search(idx, "WoRlD"), & &1.id) == ["doc1"]
    assert FuzzyIndex.terms_like(idx, "HELLO", 0) == ["hello"]
  end