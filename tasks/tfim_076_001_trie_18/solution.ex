  test "delete returns a new trie, original is unchanged" do
    t1 = Trie.new() |> Trie.insert("hello")
    t2 = Trie.delete(t1, "hello")

    assert Trie.member?(t1, "hello") == true
    assert Trie.member?(t2, "hello") == false
  end