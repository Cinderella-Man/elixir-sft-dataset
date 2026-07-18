  test "deleting a non-existent word changes nothing" do
    t = WildcardTrie.new() |> WildcardTrie.insert("bad")
    t2 = WildcardTrie.delete(t, "mad")

    assert WildcardTrie.member?(t2, "bad") == true
    assert WildcardTrie.size(t2) == 1
  end