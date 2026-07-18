  test "delete returns a new trie, original is unchanged" do
    t1 = RadixTrie.new() |> RadixTrie.insert("hello")
    t2 = RadixTrie.delete(t1, "hello")

    assert RadixTrie.member?(t1, "hello") == true
    assert RadixTrie.member?(t2, "hello") == false
  end