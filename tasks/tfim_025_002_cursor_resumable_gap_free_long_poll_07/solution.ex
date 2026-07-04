  test "missing / garbage / negative since is treated as 0", %{server: server, opts: opts} do
    Notifications.publish(server, "user:1", %{"n" => 1})

    for since <- ["", "abc", "-5", "not_a_number"] do
      conn =
        :get
        |> conn("/api/notifications/poll?since=#{since}")
        |> assign(:user_id, "user:1")
        |> NotificationRouter.call(NotificationRouter.init(opts))

      assert conn.status == 200
      assert decode(conn)["events"] == [%{"n" => 1}]
    end
  end