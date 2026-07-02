  test "insert multiple words" do
    t =
      Trie.new()
      |> Trie.insert("car")
      |> Trie.insert("card")
      |> Trie.insert("care")
      |> Trie.insert("cat")

    assert Trie.member?(t, "car") == true
    assert Trie.member?(t, "card") == true
    assert Trie.member?(t, "care") == true
    assert Trie.member?(t, "cat") == true
    assert Trie.member?(t, "ca") == false
    assert Trie.member?(t, "cars") == false
  end