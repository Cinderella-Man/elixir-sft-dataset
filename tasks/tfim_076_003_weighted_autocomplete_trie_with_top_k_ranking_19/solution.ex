  test "larger dataset — ranking across 50 words" do
    t =
      Enum.reduce(1..50, AutocompleteTrie.new(), fn i, acc ->
        AutocompleteTrie.insert(acc, "term#{String.pad_leading("#{i}", 2, "0")}", i)
      end)

    assert AutocompleteTrie.size(t) == 50
    # highest weights first: term50 (50) down to term41 (41)
    top = AutocompleteTrie.suggest(t, "term", 3)
    assert top == ["term50", "term49", "term48"]
    assert AutocompleteTrie.weight(t, "term25") == 25
  end