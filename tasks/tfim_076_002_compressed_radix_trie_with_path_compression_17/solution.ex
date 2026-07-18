  test "delete re-merges edges to restore compression" do
    t =
      RadixTrie.new()
      |> RadixTrie.insert("car")
      |> RadixTrie.insert("card")
      |> RadixTrie.insert("care")
      |> RadixTrie.insert("cat")
      |> RadixTrie.insert("dog")

    assert RadixTrie.node_count(t) == 7

    t2 = RadixTrie.delete(t, "cat")
    assert RadixTrie.member?(t2, "cat") == false
    assert RadixTrie.search(t2, "car") == ["car", "card", "care"]
    # dropping "cat" leaves "ca" with one child ("r..."), which re-merges
    assert RadixTrie.node_count(t2) == 5
  end