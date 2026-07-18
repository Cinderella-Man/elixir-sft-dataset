  test "deleting the same word twice leaves the trie empty and size at zero" do
    t =
      WildcardTrie.new()
      |> WildcardTrie.insert("bad")
      |> WildcardTrie.delete("bad")
      |> WildcardTrie.delete("bad")

    assert WildcardTrie.size(t) == 0
    assert WildcardTrie.words(t) == []
    assert WildcardTrie.member?(t, "bad") == false
    assert WildcardTrie.matches?(t, "...") == false
  end