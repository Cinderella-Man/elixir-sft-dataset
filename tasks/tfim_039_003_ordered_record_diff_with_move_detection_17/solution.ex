  test "multiple changed records are listed following new_list order" do
    old = [%{id: 1, v: 1}, %{id: 2, v: 2}, %{id: 3, v: 3}]
    new = [%{id: 3, v: 30}, %{id: 2, v: 20}, %{id: 1, v: 10}]

    %{changed: changed} = OrderedRecordDiff.diff(old, new)

    assert changed == [
             %{id: 3, changes: %{v: {3, 30}}},
             %{id: 2, changes: %{v: {2, 20}}},
             %{id: 1, changes: %{v: {1, 10}}}
           ]
  end