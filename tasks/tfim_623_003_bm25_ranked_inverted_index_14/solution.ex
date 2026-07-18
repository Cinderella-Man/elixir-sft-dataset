  test "limit caps the number of returned results", %{idx: idx} do
    for i <- 1..20 do
      :ok = InvertedIndex.index(idx, "doc#{i}", %{body: "keyword variation#{i} extra text"})
    end

    assert length(InvertedIndex.search(idx, "keyword", limit: 5)) == 5
    assert length(InvertedIndex.search(idx, "keyword")) == 20
  end