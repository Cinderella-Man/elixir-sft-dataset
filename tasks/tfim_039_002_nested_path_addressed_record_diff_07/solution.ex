  test "nested leaf added inside an existing map uses :missing old value" do
    old = [%{id: 1, address: %{city: "NYC"}}]
    new = [%{id: 1, address: %{city: "NYC", country: "US"}}]

    assert changes_for(NestedRecordDiff.diff(old, new).changed, 1) ==
             %{"address.country" => {:missing, "US"}}
  end