  test "multiple subscribers all receive the event", %{bus: bus} do
    # Spawn two helper processes that forward events back to us
    parent = self()

    sub1 =
      spawn_link(fn ->
        receive do
          msg -> send(parent, {:sub1, msg})
        end
      end)

    sub2 =
      spawn_link(fn ->
        receive do
          msg -> send(parent, {:sub2, msg})
        end
      end)

    {:ok, _} = EventBus.subscribe(bus, "topic.a", sub1)
    {:ok, _} = EventBus.subscribe(bus, "topic.a", sub2)

    EventBus.publish(bus, "topic.a", :hello)

    assert_receive {:sub1, {:event, "topic.a", :hello}}, 500
    assert_receive {:sub2, {:event, "topic.a", :hello}}, 500
  end