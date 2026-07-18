  test "publish to topic with no subscribers does not crash", %{bus: bus} do
    assert :ok = EventBus.publish(bus, "nobody.here", :hello)
  end