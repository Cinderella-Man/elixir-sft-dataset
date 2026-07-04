  test "returns 400 when channels param is missing", %{opts: opts} do
    conn =
      :get
      |> conn("/api/notifications/poll")
      |> assign(:user_id, "user:1")
      |> NotificationRouter.call(NotificationRouter.init(opts))

    assert conn.status == 400
    assert conn.resp_body == "no channels"
  end