  test "top-level and nested changes coexist" do
    old = [%{id: 1, name: "A", address: %{city: "NYC"}}]
    new = [%{id: 1, name: "Alice", address: %{city: "LA"}}]

    assert changes_for(NestedRecordDiff.diff(old, new).changed, 1) ==
             %{"name" => {"A", "Alice"}, "address.city" => {"NYC", "LA"}}
  end