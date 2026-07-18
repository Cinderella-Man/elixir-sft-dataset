  test "subscribe and publish delivers a channel-tagged message", %{server: server} do
    Notifications.subscribe(server, "user:direct", "chan")
    Notifications.publish(server, "user:direct", "chan", %{"direct" => true})
    assert_receive {:notification, "chan", %{"direct" => true}}, 500
  end