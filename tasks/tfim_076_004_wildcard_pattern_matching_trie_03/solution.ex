  test "insert and exact member?" do
    t = WildcardTrie.new() |> WildcardTrie.insert("hello")
    assert WildcardTrie.member?(t, "hello") == true
    assert WildcardTrie.member?(t, "hell") == false
    assert WildcardTrie.member?(t, "helloo") == false
    assert WildcardTrie.member?(t, "") == false
  end