  test "map appearing where the field was absent reports the whole map at the field path" do
    old = [%{id: 1, name: "A"}]
    new = [%{id: 1, name: "A", address: %{city: "NYC", zip: "10001"}}]

    assert changes_for(NestedRecordDiff.diff(old, new).changed, 1) ==
             %{"address" => {:missing, %{city: "NYC", zip: "10001"}}}
  end