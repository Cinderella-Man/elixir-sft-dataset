  test "matching across mixed lengths only returns same-length words" do
    t =
      WildcardTrie.new()
      |> WildcardTrie.insert("go")
      |> WildcardTrie.insert("god")
      |> WildcardTrie.insert("gods")

    assert WildcardTrie.matching(t, "g..") == ["god"]
    assert WildcardTrie.matching(t, "g.") == ["go"]
    assert WildcardTrie.matching(t, "g...") == ["gods"]
  end