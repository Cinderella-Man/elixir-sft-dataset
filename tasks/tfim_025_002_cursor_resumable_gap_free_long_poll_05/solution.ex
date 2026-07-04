  test "blocks and returns a notification that arrives during the poll",
       %{server: server, opts: opts} do
    task = Task.async(fn -> poll(opts, "user:1", 0) end)

    Process.sleep(100)
    Notifications.publish(server, "user:1", %{"live" => true})

    conn = Task.await(task, 2_000)
    assert conn.status == 200
    assert decode(conn) == %{"cursor" => 1, "events" => [%{"live" => true}]}
    assert cursor_header(conn) == ["1"]
  end