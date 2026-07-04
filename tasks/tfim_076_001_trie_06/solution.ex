  test "inserting the same word twice doesn't increase size" do
    t =
      Trie.new()
      |> Trie.insert("hello")
      |> Trie.insert("hello")

    assert Trie.size(t) == 1
  end