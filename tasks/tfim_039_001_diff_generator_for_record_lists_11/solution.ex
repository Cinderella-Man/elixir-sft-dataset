  test "only field-level changes: no additions or removals" do
    old = [%{id: 1, score: 10}, %{id: 2, score: 20}]
    new = [%{id: 1, score: 15}, %{id: 2, score: 25}]

    %{added: added, removed: removed, changed: changed} = RecordDiff.diff(old, new)

    assert added == []
    assert removed == []
    assert length(changed) == 2
    assert changes_for(changed, 1) == %{score: {10, 15}}
    assert changes_for(changed, 2) == %{score: {20, 25}}
  end