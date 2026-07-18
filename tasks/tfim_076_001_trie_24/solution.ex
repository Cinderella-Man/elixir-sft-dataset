  test "a duplicate insert appears only once in words and search" do
    t =
      Trie.new()
      |> Trie.insert("apple")
      |> Trie.insert("apple")
      |> Trie.insert("apply")

    assert Trie.words(t) == ["apple", "apply"]
    assert Trie.search(t, "appl") == ["apple", "apply"]
    assert Trie.size(t) == 2
  end