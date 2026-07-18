  test "scalar replaced by a map reports the whole value at the field path" do
    old = [%{id: 1, address: "unknown"}]
    new = [%{id: 1, address: %{city: "NYC"}}]

    assert changes_for(NestedRecordDiff.diff(old, new).changed, 1) ==
             %{"address" => {"unknown", %{city: "NYC"}}}
  end