  test "insert multiple words with shared prefix" do
    t =
      RadixTrie.new()
      |> RadixTrie.insert("car")
      |> RadixTrie.insert("card")
      |> RadixTrie.insert("care")
      |> RadixTrie.insert("cat")

    assert RadixTrie.member?(t, "car") == true
    assert RadixTrie.member?(t, "card") == true
    assert RadixTrie.member?(t, "care") == true
    assert RadixTrie.member?(t, "cat") == true
    assert RadixTrie.member?(t, "ca") == false
    assert RadixTrie.member?(t, "cars") == false
  end