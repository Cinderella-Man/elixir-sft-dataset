  test "single-term phrase behaves like a term query", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{title: "fox", body: "hunting"})
    assert InvertedIndex.search(idx, {:phrase, "fox"}) == ["a"]
  end