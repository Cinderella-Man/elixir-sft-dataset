  test "suggest respects limit", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "programming program problems"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "program productivity projects"})

    limited = InvertedIndex.suggest(idx, "pro", 2)
    assert length(limited) == 2
  end