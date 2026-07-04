  test "search with empty prefix returns all words sorted" do
    t =
      Trie.new()
      |> Trie.insert("banana")
      |> Trie.insert("apple")
      |> Trie.insert("cherry")

    assert Trie.search(t, "") == ["apple", "banana", "cherry"]
  end