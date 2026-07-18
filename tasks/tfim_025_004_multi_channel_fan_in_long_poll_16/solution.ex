  test "poll without :timeout_ms still validates channels", %{server: server} do
    conn =
      :get
      |> conn("/api/notifications/poll")
      |> assign(:user_id, "user:default")
      |> NotificationRouter.call(NotificationRouter.init(notifications_server: server))

    assert conn.status == 400
    assert conn.resp_body == "no channels"
  end