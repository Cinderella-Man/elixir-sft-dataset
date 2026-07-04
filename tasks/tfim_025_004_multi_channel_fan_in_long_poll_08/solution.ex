  test "returns 400 when channels param is empty", %{opts: opts} do
    conn =
      :get
      |> conn("/api/notifications/poll?channels=")
      |> assign(:user_id, "user:1")
      |> NotificationRouter.call(NotificationRouter.init(opts))

    assert conn.status == 400
  end