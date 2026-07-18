  test "deleting a prefix that exists only as a path is a no-op" do
    t = AutocompleteTrie.new() |> AutocompleteTrie.insert("card", 3)
    t2 = AutocompleteTrie.delete(t, "car")

    assert AutocompleteTrie.size(t2) == 1
    assert AutocompleteTrie.member?(t2, "card") == true
    assert AutocompleteTrie.weight(t2, "card") == 3
    assert AutocompleteTrie.words(t2) == ["card"]
    assert AutocompleteTrie.suggest(t2, "ca", 5) == ["card"]
  end