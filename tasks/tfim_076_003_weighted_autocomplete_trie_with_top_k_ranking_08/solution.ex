  test "suggest respects k and returns [] for k = 0" do
    t =
      AutocompleteTrie.new()
      |> AutocompleteTrie.insert("cat", 1)
      |> AutocompleteTrie.insert("car", 2)
      |> AutocompleteTrie.insert("card", 3)

    assert AutocompleteTrie.suggest(t, "ca", 0) == []
    assert AutocompleteTrie.suggest(t, "ca", 1) == ["card"]
    assert AutocompleteTrie.suggest(t, "ca", 2) == ["card", "car"]
  end