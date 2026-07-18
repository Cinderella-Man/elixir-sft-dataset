  test "delete of a longer word doesn't affect its prefix" do
    t =
      Trie.new()
      |> Trie.insert("car")
      |> Trie.insert("card")
      |> Trie.delete("card")

    assert Trie.member?(t, "car") == true
    assert Trie.member?(t, "card") == false
    assert Trie.size(t) == 1
  end