  test "nested boolean expressions evaluate correctly", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "the quick brown fox"})
    :ok = InvertedIndex.index(idx, "b", %{body: "the quick brown cat"})
    :ok = InvertedIndex.index(idx, "c", %{body: "a slow green turtle"})
    :ok = InvertedIndex.index(idx, "d", %{body: "fox jumps high"})

    # (cat OR fox) AND (NOT quick)  ->  only "d"
    query = {:and, [{:or, [{:term, "cat"}, {:term, "fox"}]}, {:not, {:term, "quick"}}]}
    assert InvertedIndex.search(idx, query) == ["d"]
  end