  test "new trie is empty" do
    t = AutocompleteTrie.new()
    assert AutocompleteTrie.size(t) == 0
    assert AutocompleteTrie.words(t) == []
    assert AutocompleteTrie.suggest(t, "", 5) == []
  end