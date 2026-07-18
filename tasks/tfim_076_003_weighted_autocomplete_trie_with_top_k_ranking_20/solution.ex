  test "re-inserting after delete starts weight fresh rather than resurrecting the old weight" do
    t =
      AutocompleteTrie.new()
      |> AutocompleteTrie.insert("apple", 9)
      |> AutocompleteTrie.delete("apple")
      |> AutocompleteTrie.insert("apple", 2)

    assert AutocompleteTrie.weight(t, "apple") == 2
    assert AutocompleteTrie.size(t) == 1
    assert AutocompleteTrie.suggest(t, "ap", 5) == ["apple"]
  end