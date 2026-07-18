  test "suggest rejects a negative k" do
    t = AutocompleteTrie.new() |> AutocompleteTrie.insert("cat", 1)

    assert_raise FunctionClauseError, fn -> AutocompleteTrie.suggest(t, "ca", -1) end
    assert AutocompleteTrie.suggest(t, "ca", 0) == []
  end