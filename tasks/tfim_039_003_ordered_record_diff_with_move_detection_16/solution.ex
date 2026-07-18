  test "field dropped from an existing record reports :missing on the new side" do
    old = [%{id: 1, name: "A", email: "a@x.com"}]
    new = [%{id: 1, name: "A"}]

    %{changed: changed} = OrderedRecordDiff.diff(old, new)

    assert changed == [%{id: 1, changes: %{email: {"a@x.com", :missing}}}]
  end