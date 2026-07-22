  test "exact arrival sequence is descending priority then oldest subscription",
       %{bus: bus} do
    mid_a = spawn_sub(:seq_mid_a, policy: :ack)
    low = spawn_sub(:seq_low, policy: :ack)
    high = spawn_sub(:seq_high, policy: :ack)
    mid_b = spawn_sub(:seq_mid_b, policy: :ack)

    # Subscription order deliberately unrelated to priority order; mid_a and
    # mid_b share a priority level, with mid_a subscribed first.
    sub!(bus, "t", mid_a, 5)
    sub!(bus, "t", low, 1)
    sub!(bus, "t", high, 10)
    sub!(bus, "t", mid_b, 5)

    assert {:ok, 4} = PriorityEventBus.publish(bus, "t", :evt)

    # Delivery is serial, so each notification is fully queued before the next
    # subscriber is reached: mailbox order IS delivery order.
    order = [
      next_delivered_tag(1_000),
      next_delivered_tag(1_000),
      next_delivered_tag(1_000),
      next_delivered_tag(1_000)
    ]

    assert [:seq_high, :seq_mid_a, :seq_mid_b, :seq_low] == order
  end