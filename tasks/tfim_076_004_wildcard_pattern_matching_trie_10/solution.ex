  test "matches? returns false when nothing matches" do
    t =
      WildcardTrie.new()
      |> WildcardTrie.insert("bad")
      |> WildcardTrie.insert("dad")

    assert WildcardTrie.matches?(t, ".at") == false
    assert WildcardTrie.matches?(t, "x..") == false
  end