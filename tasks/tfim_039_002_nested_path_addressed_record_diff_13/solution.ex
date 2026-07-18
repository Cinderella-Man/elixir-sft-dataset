  test "multiple nested branches change on the same record" do
    old = [%{id: 1, home: %{city: "NYC"}, work: %{city: "NJ"}}]
    new = [%{id: 1, home: %{city: "LA"}, work: %{city: "SF"}}]

    assert changes_for(NestedRecordDiff.diff(old, new).changed, 1) ==
             %{"home.city" => {"NYC", "LA"}, "work.city" => {"NJ", "SF"}}
  end