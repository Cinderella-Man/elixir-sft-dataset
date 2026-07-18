  test "delete of a prefix word doesn't affect longer words" do
    t =
      RadixTrie.new()
      |> RadixTrie.insert("car")
      |> RadixTrie.insert("card")
      |> RadixTrie.delete("car")

    assert RadixTrie.member?(t, "car") == false
    assert RadixTrie.member?(t, "card") == true
    assert RadixTrie.size(t) == 1
  end