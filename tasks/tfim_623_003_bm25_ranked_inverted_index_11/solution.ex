  test "custom stop words override the defaults", _ctx do
    {:ok, idx} = InvertedIndex.start_link(stop_words: MapSet.new(["foo", "bar"]))

    :ok = InvertedIndex.index(idx, "doc1", %{body: "foo baz bar qux"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "the quick brown"})

    assert InvertedIndex.search(idx, "foo") == []
    assert InvertedIndex.search(idx, "bar") == []
    assert length(InvertedIndex.search(idx, "the")) == 1
  end