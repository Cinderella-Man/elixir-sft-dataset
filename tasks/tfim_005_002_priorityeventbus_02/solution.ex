  test "exact-topic publish delivers to a single subscriber who acks", %{bus: bus} do
    sub = spawn_sub(:a, policy: :ack)
    _ref = sub!(bus, "orders.created", sub, 0)

    assert {:ok, 1} = PriorityEventBus.publish(bus, "orders.created", %{id: 1})
    assert_received {:got, :a, "orders.created", %{id: 1}}
  end