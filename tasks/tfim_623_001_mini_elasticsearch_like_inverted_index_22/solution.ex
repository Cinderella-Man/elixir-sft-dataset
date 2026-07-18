  test "suggest is case-insensitive", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "programming program"})

    assert length(InvertedIndex.suggest(idx, "PRO")) > 0
  end