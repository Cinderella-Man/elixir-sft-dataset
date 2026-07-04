  test "size tracks inserted words" do
    t =
      Trie.new()
      |> Trie.insert("a")
      |> Trie.insert("ab")
      |> Trie.insert("abc")

    assert Trie.size(t) == 3
  end