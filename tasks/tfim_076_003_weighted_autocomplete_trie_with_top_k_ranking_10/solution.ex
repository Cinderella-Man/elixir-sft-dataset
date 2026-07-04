  test "suggest with a prefix that matches nothing returns []" do
    t = AutocompleteTrie.new() |> AutocompleteTrie.insert("hello", 1)
    assert AutocompleteTrie.suggest(t, "xyz", 5) == []
  end