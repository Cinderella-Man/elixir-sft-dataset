  test "default server name backs the default subscribe and publish arguments" do
    start_supervised!({Notifications, []})

    Notifications.subscribe("user:default")
    assert :ok = Notifications.publish("user:default", %{"via" => "default"})

    assert_receive {:notification, %{"via" => "default"}}, 500
  end