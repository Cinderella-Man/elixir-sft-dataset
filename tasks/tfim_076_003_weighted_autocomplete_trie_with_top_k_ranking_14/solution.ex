  test "delete of a prefix word doesn't affect longer words" do
    t =
      AutocompleteTrie.new()
      |> AutocompleteTrie.insert("car", 2)
      |> AutocompleteTrie.insert("card", 3)
      |> AutocompleteTrie.delete("car")

    assert AutocompleteTrie.member?(t, "car") == false
    assert AutocompleteTrie.member?(t, "card") == true
    assert AutocompleteTrie.weight(t, "card") == 3
    assert AutocompleteTrie.size(t) == 1
    assert AutocompleteTrie.suggest(t, "ca", 5) == ["card"]
  end