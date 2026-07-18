  test "wildcard pattern also matches a stored literal dot character" do
    t =
      WildcardTrie.new()
      |> WildcardTrie.insert("b.d")
      |> WildcardTrie.insert("bad")

    assert WildcardTrie.matches?(t, "b.d") == true
    assert WildcardTrie.matching(t, "b.d") == ["b.d", "bad"]
    assert WildcardTrie.matching(t, "...") == ["b.d", "bad"]
    assert WildcardTrie.matching(t, ".a.") == ["bad"]
  end