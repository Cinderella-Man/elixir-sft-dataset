  test "insert returns a new trie, original is unchanged" do
    t1 = AutocompleteTrie.new()
    t2 = AutocompleteTrie.insert(t1, "hello", 4)

    assert AutocompleteTrie.size(t1) == 0
    assert AutocompleteTrie.weight(t1, "hello") == 0
    assert AutocompleteTrie.weight(t2, "hello") == 4
  end