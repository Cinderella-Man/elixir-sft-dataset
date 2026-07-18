  test "in-flight publish on a dying subscriber continues delivery downstream", %{bus: bus} do
    test_pid = self()

    dying =
      spawn(fn ->
        receive do
          {:event, topic, event, _reply_to} ->
            send(test_pid, {:got, :dying, topic, event})
            exit(:boom)
        end
      end)

    s_low = spawn_sub(:low, policy: :ack)

    sub!(bus, "t", dying, 100)
    sub!(bus, "t", s_low, 1)

    # The high-priority subscriber dies mid-publish without replying; the bus
    # must treat it as an ack, still count it, and deliver to the lower sub.
    assert {:ok, 2} = PriorityEventBus.publish(bus, "t", :evt)

    assert_receive {:got, :dying, "t", :evt}
    assert_receive {:got, :low, "t", :evt}
  end