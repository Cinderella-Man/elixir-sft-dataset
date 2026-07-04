  test "path compression keeps node count small" do
    t =
      RadixTrie.new()
      |> RadixTrie.insert("car")
      |> RadixTrie.insert("card")
      |> RadixTrie.insert("care")
      |> RadixTrie.insert("cat")
      |> RadixTrie.insert("dog")

    # root, "ca" node, "car" node, "card" leaf, "care" leaf, "cat" leaf, "dog" leaf
    assert RadixTrie.node_count(t) == 7
  end