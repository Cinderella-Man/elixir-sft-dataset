  test "weight of an absent word is 0" do
    t = AutocompleteTrie.new() |> AutocompleteTrie.insert("hello")
    assert AutocompleteTrie.weight(t, "world") == 0
    assert AutocompleteTrie.weight(t, "hell") == 0
  end