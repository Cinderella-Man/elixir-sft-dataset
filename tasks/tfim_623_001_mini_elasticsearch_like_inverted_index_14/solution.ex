  test "stemmed search matches morphological variants", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "walking jumps quickly"}, stem: true)
    :ok = InvertedIndex.index(idx, "doc2", %{body: "jumped walked slowly"}, stem: true)
    :ok = InvertedIndex.index(idx, "doc3", %{body: "unrelated content here"}, stem: true)

    # "walking"/"walked" → "walk" and "jumps"/"jumped" → "jump" need only the
    # spec-listed "-ing"/"-ed"/"-s" suffixes — no stemming beyond the prompt
    walk_results = InvertedIndex.search(idx, "walking", stem: true)
    assert walk_results |> Enum.map(& &1.id) |> Enum.sort() == ["doc1", "doc2"]

    jump_results = InvertedIndex.search(idx, "jumped", stem: true)
    assert jump_results |> Enum.map(& &1.id) |> Enum.sort() == ["doc1", "doc2"]
  end