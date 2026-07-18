  test "publish assigns monotonic sequences and delivers with seq", %{server: server} do
    Notifications.subscribe(server, "user:direct")

    assert {:ok, 1} = Notifications.publish(server, "user:direct", %{"a" => 1})
    assert {:ok, 2} = Notifications.publish(server, "user:direct", %{"a" => 2})

    assert_receive {:notification, 1, %{"a" => 1}}, 500
    assert_receive {:notification, 2, %{"a" => 2}}, 500
  end