  test "custom weights are respected" do
    t =
      AutocompleteTrie.new()
      |> AutocompleteTrie.insert("a", 10)
      |> AutocompleteTrie.insert("b", 2)

    assert AutocompleteTrie.weight(t, "a") == 10
    assert AutocompleteTrie.weight(t, "b") == 2
    assert AutocompleteTrie.size(t) == 2
  end