  test "multiple fields changed on the same record" do
    old = [%{id: 1, name: "Alice", age: 30, city: "NYC"}]
    new = [%{id: 1, name: "Alicia", age: 31, city: "NYC"}]

    changes = changes_for(RecordDiff.diff(old, new).changed, 1)

    assert changes == %{name: {"Alice", "Alicia"}, age: {30, 31}}
  end