  test "subscribe and publish delivers message to calling process", %{server: server} do
    Notifications.subscribe(server, "user:direct")
    Notifications.publish(server, "user:direct", %{"direct" => true})

    assert_receive {:notification, %{"direct" => true}}, 500
  end