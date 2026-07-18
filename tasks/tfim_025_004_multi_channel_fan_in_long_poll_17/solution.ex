  test "401 response carries the unauthorized body", %{opts: opts} do
    conn =
      :get
      |> conn("/api/notifications/poll?channels=a")
      |> NotificationRouter.call(NotificationRouter.init(opts))

    assert conn.status == 401
    assert conn.resp_body == "unauthorized"
  end