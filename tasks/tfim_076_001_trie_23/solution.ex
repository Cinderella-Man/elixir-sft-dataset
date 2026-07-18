  test "re-inserting a word after it was deleted restores it" do
    t =
      Trie.new()
      |> Trie.insert("car")
      |> Trie.insert("card")
      |> Trie.delete("card")
      |> Trie.insert("card")

    assert Trie.member?(t, "card") == true
    assert Trie.member?(t, "car") == true
    assert Trie.size(t) == 2
    assert Trie.search(t, "car") == ["car", "card"]
  end