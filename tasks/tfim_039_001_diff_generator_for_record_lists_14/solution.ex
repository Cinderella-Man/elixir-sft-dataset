  test "field removed from existing record is reported as change with :missing new value" do
    old = [%{id: 1, name: "Alice", email: "alice@example.com"}]
    new = [%{id: 1, name: "Alice"}]

    changes = changes_for(RecordDiff.diff(old, new).changed, 1)

    assert changes == %{email: {"alice@example.com", :missing}}
  end