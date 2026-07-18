  test "suggest respects limit and is case-insensitive", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "d1", %{body: "programming program problems"})
    :ok = InvertedIndex.index(idx, "d2", %{body: "program productivity projects"})

    assert length(InvertedIndex.suggest(idx, "pro", 2)) == 2
    assert length(InvertedIndex.suggest(idx, "PRO")) > 0
  end