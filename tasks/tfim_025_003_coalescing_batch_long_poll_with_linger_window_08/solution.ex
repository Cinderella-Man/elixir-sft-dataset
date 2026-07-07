  test "correct user receives their batch among many pollers", %{server: server, opts: opts} do
    task_a = Task.async(fn -> poll(opts, "user:a") end)
    task_b = Task.async(fn -> poll(opts, "user:b") end)
    Process.sleep(100)

    Notifications.publish(server, "user:b", %{"m" => 1})
    Notifications.publish(server, "user:b", %{"m" => 2})

    conn_b = Task.await(task_b, 2_000)
    assert conn_b.status == 200
    assert Jason.decode!(conn_b.resp_body)["count"] == 2

    conn_a = Task.await(task_a, 2_000)
    assert conn_a.status == 204
  end