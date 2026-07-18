  test "matching with no wildcard returns at most the exact word" do
    t =
      WildcardTrie.new()
      |> WildcardTrie.insert("dad")
      |> WildcardTrie.insert("dot")

    assert WildcardTrie.matching(t, "dad") == ["dad"]
    assert WildcardTrie.matching(t, "dab") == []
  end