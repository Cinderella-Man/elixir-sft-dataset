  test "custom :key option uses a different field as the record identifier" do
    old = [%{uuid: "aaa", value: 1}]
    new = [%{uuid: "aaa", value: 2}, %{uuid: "bbb", value: 9}]

    %{added: added, removed: removed, changed: changed} =
      RecordDiff.diff(old, new, key: :uuid)

    assert length(added) == 1
    assert hd(added).uuid == "bbb"
    assert removed == []
    assert length(changed) == 1
    assert hd(changed).uuid == "aaa"
    assert hd(changed).changes == %{value: {1, 2}}
  end