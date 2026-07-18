  test "delete of a word doesn't affect same-length siblings" do
    t =
      WildcardTrie.new()
      |> WildcardTrie.insert("bad")
      |> WildcardTrie.insert("dad")
      |> WildcardTrie.insert("mad")
      |> WildcardTrie.delete("bad")

    assert WildcardTrie.matching(t, ".ad") == ["dad", "mad"]
    assert WildcardTrie.size(t) == 2
  end