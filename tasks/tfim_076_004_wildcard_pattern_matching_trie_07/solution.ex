  test "matches? with a leading wildcard" do
    t =
      WildcardTrie.new()
      |> WildcardTrie.insert("bad")
      |> WildcardTrie.insert("dad")
      |> WildcardTrie.insert("mad")

    assert WildcardTrie.matches?(t, ".ad") == true
    assert WildcardTrie.matches?(t, "b..") == true
    assert WildcardTrie.matches?(t, "...") == true
    assert WildcardTrie.matches?(t, "..d") == true
  end