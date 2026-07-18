  test "single character words" do
    t =
      Trie.new()
      |> Trie.insert("a")
      |> Trie.insert("b")
      |> Trie.insert("c")

    assert Trie.size(t) == 3
    assert Trie.member?(t, "a") == true
    assert Trie.search(t, "a") == ["a"]
  end