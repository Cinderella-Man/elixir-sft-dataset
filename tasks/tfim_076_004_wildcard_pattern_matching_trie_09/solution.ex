  test "matches? with no wildcard behaves like exact lookup" do
    t = WildcardTrie.new() |> WildcardTrie.insert("bad")
    assert WildcardTrie.matches?(t, "bad") == true
    assert WildcardTrie.matches?(t, "bat") == false
  end