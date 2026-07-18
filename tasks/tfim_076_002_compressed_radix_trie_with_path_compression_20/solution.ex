  test "insert returns a new trie, original is unchanged" do
    t1 = RadixTrie.new()
    t2 = RadixTrie.insert(t1, "hello")

    assert RadixTrie.size(t1) == 0
    assert RadixTrie.member?(t1, "hello") == false
    assert RadixTrie.size(t2) == 1
    assert RadixTrie.member?(t2, "hello") == true
  end