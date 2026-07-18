  test "buffer retains only the most recent :buffer_size events" do
    server = :"notifications_#{System.unique_integer([:positive])}"
    start_supervised!({Notifications, name: server, buffer_size: 3})

    for n <- 1..5, do: Notifications.publish(server, "user:1", %{"n" => n})

    # Only seqs 3,4,5 survive; asking since 0 still returns them oldest-first.
    events = Notifications.events_since(server, "user:1", 0)
    assert events == [{3, %{"n" => 3}}, {4, %{"n" => 4}}, {5, %{"n" => 5}}]
  end