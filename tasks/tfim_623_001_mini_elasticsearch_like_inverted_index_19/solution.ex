  test "suggest returns terms matching the prefix sorted by doc frequency", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "programming program problems"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "program productivity projects"})
    :ok = InvertedIndex.index(idx, "doc3", %{body: "testing productivity"})

    suggestions = InvertedIndex.suggest(idx, "pro")
    assert length(suggestions) > 0
    assert Enum.all?(suggestions, &String.starts_with?(&1, "pro"))

    # "program" in 2 docs, "productivity" in 2 docs → both should come before
    # "programming", "problems", "projects" (each in 1 doc)
    top_two = Enum.take(suggestions, 2)
    assert "program" in top_two
    assert "productivity" in top_two
  end