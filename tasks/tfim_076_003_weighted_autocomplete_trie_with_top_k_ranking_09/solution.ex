  test "suggest includes the prefix itself when inserted" do
    t =
      AutocompleteTrie.new()
      |> AutocompleteTrie.insert("go", 4)
      |> AutocompleteTrie.insert("gopher", 1)

    assert AutocompleteTrie.suggest(t, "go", 5) == ["go", "gopher"]
  end