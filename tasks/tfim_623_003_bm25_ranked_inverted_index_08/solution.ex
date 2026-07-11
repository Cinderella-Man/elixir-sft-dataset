  test "shorter document with equal term frequency ranks higher", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "long", %{body: "fox padding padding padding"})
    :ok = InvertedIndex.index(idx, "short", %{body: "fox"})

    results = InvertedIndex.search(idx, "fox")
    assert Enum.map(results, & &1.id) == ["short", "long"]
  end