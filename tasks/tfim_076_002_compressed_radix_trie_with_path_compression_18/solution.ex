  test "deleting a non-existent word changes nothing" do
    t = RadixTrie.new() |> RadixTrie.insert("hello")
    t2 = RadixTrie.delete(t, "world")

    assert RadixTrie.member?(t2, "hello") == true
    assert RadixTrie.size(t2) == 1
  end