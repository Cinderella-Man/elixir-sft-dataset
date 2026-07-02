  test "new trie is empty" do
    t = Trie.new()
    assert Trie.size(t) == 0
    assert Trie.words(t) == []
  end