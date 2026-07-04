  test "inserting the same word twice doesn't increase size" do
    t =
      RadixTrie.new()
      |> RadixTrie.insert("hello")
      |> RadixTrie.insert("hello")

    assert RadixTrie.size(t) == 1
    assert RadixTrie.node_count(t) == 2
  end