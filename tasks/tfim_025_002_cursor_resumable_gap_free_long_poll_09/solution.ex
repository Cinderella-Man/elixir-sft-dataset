  test "events for user A do not leak to user B", %{server: server, opts: opts} do
    task_b = Task.async(fn -> poll(opts, "user:b", 0) end)

    Process.sleep(100)
    Notifications.publish(server, "user:a", %{"for" => "a"})

    conn_b = Task.await(task_b, 2_000)
    assert conn_b.status == 204
    assert cursor_header(conn_b) == ["0"]
  end