  test "insert and member? for a single word" do
    t = Trie.new() |> Trie.insert("hello")
    assert Trie.member?(t, "hello") == true
    assert Trie.member?(t, "hell") == false
    assert Trie.member?(t, "helloo") == false
    assert Trie.member?(t, "") == false
  end