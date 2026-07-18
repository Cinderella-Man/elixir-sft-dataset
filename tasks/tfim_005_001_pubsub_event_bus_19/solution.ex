  test "can start with a :name and use that name" do
    {:ok, _pid} = EventBus.start_link(name: :my_bus)

    {:ok, _ref} = EventBus.subscribe(:my_bus, "t", self())
    :ok = EventBus.publish(:my_bus, "t", :named)

    assert_receive {:event, "t", :named}, 500
  end