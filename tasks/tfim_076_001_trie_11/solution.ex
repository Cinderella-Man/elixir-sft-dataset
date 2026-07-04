  test "words returns all inserted words sorted" do
    t =
      Trie.new()
      |> Trie.insert("zebra")
      |> Trie.insert("apple")
      |> Trie.insert("mango")
      |> Trie.insert("apricot")

    assert Trie.words(t) == ["apple", "apricot", "mango", "zebra"]
  end