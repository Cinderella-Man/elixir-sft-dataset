  test "deleting the same word twice leaves the count at zero" do
    t =
      Trie.new()
      |> Trie.insert("hello")
      |> Trie.delete("hello")
      |> Trie.delete("hello")

    assert Trie.size(t) == 0
    assert Trie.member?(t, "hello") == false
    assert Trie.words(t) == []
  end