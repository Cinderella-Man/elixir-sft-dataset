  test "field added to existing record is reported as change with :missing old value" do
    old = [%{id: 1, name: "Alice"}]
    new = [%{id: 1, name: "Alice", email: "alice@example.com"}]

    changes = changes_for(RecordDiff.diff(old, new).changed, 1)

    assert changes == %{email: {:missing, "alice@example.com"}}
  end