  test "mixed scenario: additions, removals, and changes together" do
    old = [
      %{id: 1, name: "Alice", age: 30},
      %{id: 2, name: "Bob", age: 25},
      %{id: 3, name: "Carol", age: 40}
    ]

    new = [
      %{id: 1, name: "Alice", age: 31},
      %{id: 3, name: "Carol", age: 40},
      %{id: 4, name: "Dave", age: 22}
    ]

    %{added: added, removed: removed, changed: changed} = RecordDiff.diff(old, new)

    assert length(added) == 1
    assert hd(added).id == 4

    assert length(removed) == 1
    assert hd(removed).id == 2

    assert length(changed) == 1
    assert hd(changed).id == 1
    assert hd(changed).changes == %{age: {30, 31}}
  end