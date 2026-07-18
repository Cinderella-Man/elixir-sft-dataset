  test "empty string is storable and retrievable like any other word" do
    t = WildcardTrie.new() |> WildcardTrie.insert("")

    assert WildcardTrie.member?(t, "") == true
    assert WildcardTrie.size(t) == 1
    assert WildcardTrie.words(t) == [""]
    assert WildcardTrie.matches?(t, "") == true
    assert WildcardTrie.matching(t, "") == [""]

    t2 = WildcardTrie.delete(t, "")
    assert WildcardTrie.member?(t2, "") == false
    assert WildcardTrie.size(t2) == 0
  end