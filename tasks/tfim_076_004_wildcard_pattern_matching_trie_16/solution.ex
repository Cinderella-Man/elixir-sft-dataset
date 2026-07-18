  test "delete of a prefix word doesn't affect longer words" do
    t =
      WildcardTrie.new()
      |> WildcardTrie.insert("go")
      |> WildcardTrie.insert("god")
      |> WildcardTrie.delete("go")

    assert WildcardTrie.member?(t, "go") == false
    assert WildcardTrie.member?(t, "god") == true
    assert WildcardTrie.matching(t, "g..") == ["god"]
    assert WildcardTrie.size(t) == 1
  end