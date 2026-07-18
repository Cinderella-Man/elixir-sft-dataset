  test "events for unknown aggregate returns empty list", %{agg: agg} do
    assert TaskAggregate.events(agg, "nonexistent") == []
  end