  test "401 when user_id is absent", %{opts: opts} do
    conn =
      :get
      |> conn("/api/notifications/poll?since=0")
      |> NotificationRouter.call(NotificationRouter.init(opts))

    assert conn.status == 401
    assert conn.resp_body == "unauthorized"
  end