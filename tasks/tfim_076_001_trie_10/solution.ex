  test "search on empty trie returns empty list" do
    assert Trie.search(Trie.new(), "a") == []
  end