  test "delete returns a new trie, original is unchanged" do
    t1 = WildcardTrie.new() |> WildcardTrie.insert("bad")
    t2 = WildcardTrie.delete(t1, "bad")

    assert WildcardTrie.member?(t1, "bad") == true
    assert WildcardTrie.member?(t2, "bad") == false
  end