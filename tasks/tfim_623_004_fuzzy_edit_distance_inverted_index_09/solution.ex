  test "custom stop words override the defaults" do
    {:ok, idx} = FuzzyIndex.start_link(stop_words: MapSet.new(["foo", "bar"]))

    :ok = FuzzyIndex.index(idx, "doc1", "foo baz bar qux")
    :ok = FuzzyIndex.index(idx, "doc2", "the quick")

    # "foo" and "bar" are stop words under the custom set
    assert FuzzyIndex.search(idx, "foo") == []
    assert FuzzyIndex.search(idx, "bar") == []

    # "the" is NOT a stop word under the custom set, so it is indexed
    assert length(FuzzyIndex.search(idx, "the")) == 1
  end