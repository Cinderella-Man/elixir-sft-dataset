  test "deleting a non-existent word changes nothing" do
    t = Trie.new() |> Trie.insert("hello")
    t2 = Trie.delete(t, "world")

    assert Trie.member?(t2, "hello") == true
    assert Trie.size(t2) == 1
  end