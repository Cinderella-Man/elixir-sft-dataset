  test "custom :key option uses a different identifier field" do
    old = [%{uuid: "aaa", meta: %{v: 1}}]
    new = [%{uuid: "aaa", meta: %{v: 2}}, %{uuid: "bbb", meta: %{v: 9}}]

    %{added: added, changed: changed} = NestedRecordDiff.diff(old, new, key: :uuid)

    assert added == [%{uuid: "bbb", meta: %{v: 9}}]
    assert length(changed) == 1
    assert hd(changed).uuid == "aaa"
    assert hd(changed).changes == %{"meta.v" => {1, 2}}
  end