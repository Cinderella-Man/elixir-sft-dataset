  test "nested leaf removed inside an existing map uses :missing new value" do
    old = [%{id: 1, address: %{city: "NYC", country: "US"}}]
    new = [%{id: 1, address: %{city: "NYC"}}]

    assert changes_for(NestedRecordDiff.diff(old, new).changed, 1) ==
             %{"address.country" => {"US", :missing}}
  end