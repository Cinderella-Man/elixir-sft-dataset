  test "nested map replaced by a scalar deeper down does not recurse" do
    old = [%{id: 1, a: %{b: %{c: 1, d: 2}}}]
    new = [%{id: 1, a: %{b: 5}}]

    assert changes_for(NestedRecordDiff.diff(old, new).changed, 1) ==
             %{"a.b" => {%{c: 1, d: 2}, 5}}
  end