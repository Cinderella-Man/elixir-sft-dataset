  test "multiple buffered events replay in order with the highest cursor",
       %{server: server, opts: opts} do
    assert {:ok, 1} = Notifications.publish(server, "user:1", %{"n" => 1})
    assert {:ok, 2} = Notifications.publish(server, "user:1", %{"n" => 2})
    assert {:ok, 3} = Notifications.publish(server, "user:1", %{"n" => 3})

    conn = poll(opts, "user:1", 0)

    assert conn.status == 200

    assert decode(conn) == %{
             "cursor" => 3,
             "events" => [%{"n" => 1}, %{"n" => 2}, %{"n" => 3}]
           }

    assert cursor_header(conn) == ["3"]
  end