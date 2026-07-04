  test "insert and member? for a single word" do
    t = RadixTrie.new() |> RadixTrie.insert("hello")
    assert RadixTrie.member?(t, "hello") == true
    assert RadixTrie.member?(t, "hell") == false
    assert RadixTrie.member?(t, "helloo") == false
    assert RadixTrie.member?(t, "") == false
    # one edge "hello" => root + leaf
    assert RadixTrie.node_count(t) == 2
  end