  test "router returns 404 for unknown paths", %{opts: opts} do
    conn =
      :get
      |> conn("/api/unknown")
      |> NotificationRouter.call(NotificationRouter.init(opts))

    assert conn.status == 404
  end