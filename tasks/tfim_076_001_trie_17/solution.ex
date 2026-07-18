  test "insert returns a new trie, original is unchanged" do
    t1 = Trie.new()
    t2 = Trie.insert(t1, "hello")

    assert Trie.size(t1) == 0
    assert Trie.member?(t1, "hello") == false

    assert Trie.size(t2) == 1
    assert Trie.member?(t2, "hello") == true
  end