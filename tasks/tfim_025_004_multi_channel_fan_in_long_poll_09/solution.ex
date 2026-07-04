  test "same channel name is isolated per user", %{server: server, opts: opts} do
    task_b = Task.async(fn -> poll(opts, "user:b", ["shared"]) end)
    Process.sleep(100)
    Notifications.publish(server, "user:a", "shared", %{"for" => "a"})

    conn_b = Task.await(task_b, 2_000)
    assert conn_b.status == 204
  end