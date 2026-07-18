  test "deleting car leaves card fully intact" do
    t =
      WildcardTrie.new()
      |> WildcardTrie.insert("car")
      |> WildcardTrie.insert("card")
      |> WildcardTrie.delete("car")

    assert WildcardTrie.member?(t, "car") == false
    assert WildcardTrie.member?(t, "card") == true
    assert WildcardTrie.matching(t, "car.") == ["card"]
    assert WildcardTrie.matching(t, "...") == []
    assert WildcardTrie.words(t) == ["card"]
    assert WildcardTrie.size(t) == 1
  end