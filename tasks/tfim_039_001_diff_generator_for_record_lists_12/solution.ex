  test "unchanged records do not appear in :changed" do
    old = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]
    new = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bobby"}]

    %{changed: changed} = RecordDiff.diff(old, new)

    assert length(changed) == 1
    assert hd(changed).id == 2
  end