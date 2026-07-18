  test "removed document no longer appears", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "quick brown fox"})
    :ok = InvertedIndex.index(idx, "b", %{body: "quick brown cat"})
    :ok = InvertedIndex.index(idx, "c", %{body: "slow turtle"})

    :ok = InvertedIndex.remove(idx, "b")

    assert InvertedIndex.search(idx, {:term, "quick"}) == ["a"]
    assert InvertedIndex.stats(idx).document_count == 2
  end