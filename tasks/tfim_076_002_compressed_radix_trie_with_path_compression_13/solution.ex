  test "search on empty trie returns empty list" do
    assert RadixTrie.search(RadixTrie.new(), "a") == []
  end