  test "a burst for user A is not delivered to user B", %{server: server, opts: opts} do
    task_b = Task.async(fn -> poll(opts, "user:b") end)
    Process.sleep(100)

    Notifications.publish(server, "user:a", %{"for" => "a"})
    Notifications.publish(server, "user:a", %{"for" => "a2"})

    conn_b = Task.await(task_b, 2_000)
    assert conn_b.status == 204
  end