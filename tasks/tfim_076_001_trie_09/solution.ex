  test "search with prefix that matches nothing returns empty list" do
    t = Trie.new() |> Trie.insert("hello")
    assert Trie.search(t, "xyz") == []
  end