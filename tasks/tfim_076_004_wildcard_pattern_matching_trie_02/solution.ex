  test "new trie is empty" do
    t = WildcardTrie.new()
    assert WildcardTrie.size(t) == 0
    assert WildcardTrie.words(t) == []
    assert WildcardTrie.matches?(t, "a") == false
    assert WildcardTrie.matching(t, "a") == []
  end