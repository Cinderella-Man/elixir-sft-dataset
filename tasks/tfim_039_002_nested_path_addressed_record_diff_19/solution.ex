  test "added, removed and changed records are reported together in one diff" do
    old = [
      %{id: 1, a: %{b: 1}},
      %{id: 2, a: %{b: 2}},
      %{id: 3, a: %{b: 3}}
    ]

    new = [
      %{id: 1, a: %{b: 1}},
      %{id: 3, a: %{b: 30}},
      %{id: 4, a: %{b: 4}}
    ]

    %{added: added, removed: removed, changed: changed} = NestedRecordDiff.diff(old, new)

    assert added == [%{id: 4, a: %{b: 4}}]
    assert removed == [%{id: 2, a: %{b: 2}}]
    assert length(changed) == 1
    assert hd(changed).id == 3
    assert hd(changed).changes == %{"a.b" => {3, 30}}
  end