  test "unsubscribed sub no longer receives events", %{bus: bus} do
    sub = spawn_sub(:a, policy: :ack)
    ref = sub!(bus, "t", sub, 0)

    :ok = PriorityEventBus.unsubscribe(bus, "t", ref)

    assert {:ok, 0} = PriorityEventBus.publish(bus, "t", :evt)
    refute_received {:got, :a, _, _}
  end