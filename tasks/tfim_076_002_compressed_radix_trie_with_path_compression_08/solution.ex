  test "edge splitting on partial overlap" do
    t =
      RadixTrie.new()
      |> RadixTrie.insert("test")
      |> RadixTrie.insert("team")

    assert RadixTrie.member?(t, "test") == true
    assert RadixTrie.member?(t, "team") == true
    assert RadixTrie.member?(t, "te") == false
    # root, "te" branch, "st" leaf, "am" leaf
    assert RadixTrie.node_count(t) == 4
  end