  test "nested leaf change is reported with a dotted path" do
    old = [%{id: 1, name: "A", address: %{city: "NYC", zip: "10001"}}]
    new = [%{id: 1, name: "A", address: %{city: "LA", zip: "10001"}}]

    assert changes_for(NestedRecordDiff.diff(old, new).changed, 1) ==
             %{"address.city" => {"NYC", "LA"}}
  end