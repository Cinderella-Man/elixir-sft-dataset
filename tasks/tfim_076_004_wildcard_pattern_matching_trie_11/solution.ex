  test "matching returns all matches sorted" do
    t =
      WildcardTrie.new()
      |> WildcardTrie.insert("bad")
      |> WildcardTrie.insert("dad")
      |> WildcardTrie.insert("mad")
      |> WildcardTrie.insert("pad")
      |> WildcardTrie.insert("pat")

    assert WildcardTrie.matching(t, ".ad") == ["bad", "dad", "mad", "pad"]
    assert WildcardTrie.matching(t, "pa.") == ["pad", "pat"]
    assert WildcardTrie.matching(t, "p..") == ["pad", "pat"]
    assert WildcardTrie.matching(t, "...") == ["bad", "dad", "mad", "pad", "pat"]
  end