  test "custom stop words override the defaults", _ctx do
    {:ok, idx} = InvertedIndex.start_link(stop_words: MapSet.new(["foo", "bar"]))

    :ok = InvertedIndex.index(idx, "a", %{body: "foo baz bar qux"})
    :ok = InvertedIndex.index(idx, "b", %{body: "the quick brown"})

    assert InvertedIndex.search(idx, {:term, "foo"}) == []
    assert InvertedIndex.search(idx, {:term, "bar"}) == []
    # "the" is NOT a stop word under the custom set
    assert InvertedIndex.search(idx, {:term, "the"}) == ["b"]
  end