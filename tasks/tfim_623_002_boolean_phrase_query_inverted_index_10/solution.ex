  test "results are sorted ascending by id", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "c", %{body: "keyword"})
    :ok = InvertedIndex.index(idx, "a", %{body: "keyword"})
    :ok = InvertedIndex.index(idx, "b", %{body: "keyword"})

    assert InvertedIndex.search(idx, {:term, "keyword"}) == ["a", "b", "c"]
  end