  test "limit caps number of returned results", %{idx: idx} do
    for i <- 1..20 do
      :ok = InvertedIndex.index(idx, "doc#{i}", %{body: "keyword variation#{i} extra text"})
    end

    limited = InvertedIndex.search(idx, "keyword", limit: 5)
    assert length(limited) == 5

    unlimited = InvertedIndex.search(idx, "keyword")
    assert length(unlimited) == 20
  end