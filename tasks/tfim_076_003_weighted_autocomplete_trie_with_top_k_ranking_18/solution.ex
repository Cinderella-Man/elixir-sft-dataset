  test "delete returns a new trie, original is unchanged" do
    t1 = AutocompleteTrie.new() |> AutocompleteTrie.insert("hello", 1)
    t2 = AutocompleteTrie.delete(t1, "hello")

    assert AutocompleteTrie.member?(t1, "hello") == true
    assert AutocompleteTrie.member?(t2, "hello") == false
  end