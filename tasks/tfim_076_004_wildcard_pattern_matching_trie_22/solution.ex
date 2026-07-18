  test "member? finds a stored word that contains a literal dot" do
    t =
      WildcardTrie.new()
      |> WildcardTrie.insert("b.d")
      |> WildcardTrie.insert("bad")

    assert WildcardTrie.member?(t, "b.d") == true
    assert WildcardTrie.member?(t, "bad") == true
    assert WildcardTrie.size(t) == 2

    only_dot = WildcardTrie.new() |> WildcardTrie.insert("b.d")
    assert WildcardTrie.member?(only_dot, "b.d") == true
    assert WildcardTrie.member?(only_dot, "bad") == false
  end