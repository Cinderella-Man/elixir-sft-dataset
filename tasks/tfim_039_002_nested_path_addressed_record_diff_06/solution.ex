  test "deeply nested leaf change builds a multi-segment path" do
    old = [%{id: 1, a: %{b: %{c: 1}}}]
    new = [%{id: 1, a: %{b: %{c: 2}}}]

    assert changes_for(NestedRecordDiff.diff(old, new).changed, 1) ==
             %{"a.b.c" => {1, 2}}
  end