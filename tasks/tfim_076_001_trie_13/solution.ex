  test "delete of a prefix word doesn't affect longer words" do
    t =
      Trie.new()
      |> Trie.insert("car")
      |> Trie.insert("card")
      |> Trie.delete("car")

    assert Trie.member?(t, "car") == false
    assert Trie.member?(t, "card") == true
    assert Trie.size(t) == 1
  end