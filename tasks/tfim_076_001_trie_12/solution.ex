  test "delete removes a word" do
    t =
      Trie.new()
      |> Trie.insert("hello")
      |> Trie.delete("hello")

    assert Trie.member?(t, "hello") == false
    assert Trie.size(t) == 0
  end