  test "search for a prefix that runs past a stored word returns no words" do
    t =
      Trie.new()
      |> Trie.insert("hello")
      |> Trie.insert("help")

    assert Trie.search(t, "helloworld") == []
    assert Trie.search(t, "hell") == ["hello"]
    assert Trie.search(t, "hel") == ["hello", "help"]
  end