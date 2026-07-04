  test "unchanged nested records do not appear in :changed" do
    old = [%{id: 1, a: %{b: 1}}, %{id: 2, a: %{b: 2}}]
    new = [%{id: 1, a: %{b: 1}}, %{id: 2, a: %{b: 99}}]

    %{changed: changed} = NestedRecordDiff.diff(old, new)

    assert length(changed) == 1
    assert hd(changed).id == 2
    assert hd(changed).changes == %{"a.b" => {2, 99}}
  end