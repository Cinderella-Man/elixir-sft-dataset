  test "default key is :id even when records also carry a uuid field" do
    old = [%{id: 1, uuid: "aaa", meta: %{v: 1}}]
    new = [%{id: 1, uuid: "bbb", meta: %{v: 2}}]

    %{added: added, removed: removed, changed: changed} = NestedRecordDiff.diff(old, new)

    assert added == []
    assert removed == []
    assert length(changed) == 1
    assert hd(changed).id == 1
    assert hd(changed).changes == %{"uuid" => {"aaa", "bbb"}, "meta.v" => {1, 2}}
  end