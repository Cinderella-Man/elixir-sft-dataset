  test "events_since filters strictly greater than cursor", %{server: server} do
    Notifications.publish(server, "user:1", %{"n" => 1})
    Notifications.publish(server, "user:1", %{"n" => 2})
    Notifications.publish(server, "user:1", %{"n" => 3})

    assert Notifications.events_since(server, "user:1", 0) ==
             [{1, %{"n" => 1}}, {2, %{"n" => 2}}, {3, %{"n" => 3}}]

    assert Notifications.events_since(server, "user:1", 2) == [{3, %{"n" => 3}}]
    assert Notifications.events_since(server, "user:1", 3) == []
  end