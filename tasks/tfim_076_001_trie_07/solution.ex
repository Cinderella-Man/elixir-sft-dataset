  test "search returns all words with the given prefix, sorted" do
    t =
      Trie.new()
      |> Trie.insert("car")
      |> Trie.insert("card")
      |> Trie.insert("care")
      |> Trie.insert("careful")
      |> Trie.insert("cat")
      |> Trie.insert("dog")

    assert Trie.search(t, "car") == ["car", "card", "care", "careful"]
    assert Trie.search(t, "care") == ["care", "careful"]
    assert Trie.search(t, "cat") == ["cat"]
    assert Trie.search(t, "d") == ["dog"]
  end