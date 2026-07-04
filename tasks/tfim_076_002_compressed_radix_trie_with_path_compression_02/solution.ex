  test "new trie is empty" do
    t = RadixTrie.new()
    assert RadixTrie.size(t) == 0
    assert RadixTrie.words(t) == []
    assert RadixTrie.node_count(t) == 1
  end