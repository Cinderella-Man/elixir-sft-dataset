  test "insert returns a new trie, original is unchanged" do
    t1 = WildcardTrie.new()
    t2 = WildcardTrie.insert(t1, "bad")

    assert WildcardTrie.size(t1) == 0
    assert WildcardTrie.member?(t1, "bad") == false
    assert WildcardTrie.member?(t2, "bad") == true
  end