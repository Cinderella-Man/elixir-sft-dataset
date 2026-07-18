  test "field omitted from the boosts map is weighted exactly one", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{title: "cat", body: "fox"})
    :ok = InvertedIndex.index(idx, "doc2", %{title: "fox", body: "cat"})

    partial = InvertedIndex.search(idx, "fox", boosts: %{title: 3})
    explicit = InvertedIndex.search(idx, "fox", boosts: %{title: 3, body: 1})

    assert Enum.map(partial, & &1.id) == ["doc2", "doc1"]
    assert Enum.map(partial, & &1.id) == Enum.map(explicit, & &1.id)

    for {p, e} <- Enum.zip(partial, explicit) do
      assert_in_delta p.score, e.score, 1.0e-9
    end
  end