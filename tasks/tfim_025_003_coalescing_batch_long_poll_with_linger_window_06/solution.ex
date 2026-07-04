  test "returns 401 when user_id is not in assigns", %{opts: opts} do
    conn =
      :get
      |> conn("/api/notifications/poll")
      |> NotificationRouter.call(NotificationRouter.init(opts))

    assert conn.status == 401
  end