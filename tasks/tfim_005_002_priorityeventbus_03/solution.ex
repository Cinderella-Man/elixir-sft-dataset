  test "non-matching topic is not delivered (exact match only)", %{bus: bus} do
    sub = spawn_sub(:a)
    _ = sub!(bus, "orders.created", sub, 0)

    # "orders.*" is NOT a wildcard in this module
    assert {:ok, 0} = PriorityEventBus.publish(bus, "orders.updated", %{})
    refute_received {:got, :a, _, _}

    # Verify "*" is also treated as a literal string
    _ = sub!(bus, "*", sub, 0)
    assert {:ok, 0} = PriorityEventBus.publish(bus, "orders.updated", %{})
    refute_received {:got, :a, _, _}
  end