  test "events for unknown aggregate returns empty list", %{agg: agg} do
    assert Aggregate.events(agg, "nonexistent") == []
  end