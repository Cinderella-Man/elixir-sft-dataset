  test "suggest returns prefix matches sorted by document frequency", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "d1", %{body: "programming program problems"})
    :ok = InvertedIndex.index(idx, "d2", %{body: "program productivity projects"})
    :ok = InvertedIndex.index(idx, "d3", %{body: "testing productivity"})

    suggestions = InvertedIndex.suggest(idx, "pro")
    assert Enum.all?(suggestions, &String.starts_with?(&1, "pro"))

    # "program" (2 docs) and "productivity" (2 docs) rank above the 1-doc terms
    top_two = Enum.take(suggestions, 2)
    assert "program" in top_two
    assert "productivity" in top_two
  end