  test "limit caps the number of returned results", %{idx: idx} do
    for i <- 1..20 do
      :ok = FuzzyIndex.index(idx, "doc#{i}", "keyword variation#{i} extra text")
    end

    assert length(FuzzyIndex.search(idx, "keyword", limit: 5)) == 5
    assert length(FuzzyIndex.search(idx, "keyword")) == 20
  end