  test "document with only stop words is not searchable", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "stoponly", %{body: "the a an is are was"})

    assert InvertedIndex.search(idx, "the") == []
    assert InvertedIndex.search(idx, "is") == []
  end