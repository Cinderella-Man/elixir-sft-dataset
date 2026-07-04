  test "field added/removed on an existing record uses :missing" do
    old = [%{id: 1, name: "A"}]
    new = [%{id: 1, name: "A", email: "a@x.com"}]

    %{changed: changed} = OrderedRecordDiff.diff(old, new)

    assert changed == [%{id: 1, changes: %{email: {:missing, "a@x.com"}}}]
  end