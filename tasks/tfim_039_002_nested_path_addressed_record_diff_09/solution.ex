  test "map replaced by a scalar reports the whole value at the field path" do
    old = [%{id: 1, address: %{city: "NYC"}}]
    new = [%{id: 1, address: "unknown"}]

    assert changes_for(NestedRecordDiff.diff(old, new).changed, 1) ==
             %{"address" => {%{city: "NYC"}, "unknown"}}
  end