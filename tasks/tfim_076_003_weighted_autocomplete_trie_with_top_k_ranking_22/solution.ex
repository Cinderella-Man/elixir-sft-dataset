  test "insert rejects non-positive and non-integer weights" do
    t = AutocompleteTrie.new()

    assert_raise FunctionClauseError, fn -> AutocompleteTrie.insert(t, "a", 0) end
    assert_raise FunctionClauseError, fn -> AutocompleteTrie.insert(t, "a", -5) end
    assert_raise FunctionClauseError, fn -> AutocompleteTrie.insert(t, "a", 1.5) end
  end