  test "multiple pollers for the same user all receive the notification", %{server: server, opts: opts} do
    task1 = Task.async(fn -> poll(opts, "user:1") end)
    task2 = Task.async(fn -> poll(opts, "user:1") end)

    Process.sleep(100)

    Notifications.publish(server, "user:1", %{"n" => 1})

    conn1 = Task.await(task1, 2_000)
    conn2 = Task.await(task2, 2_000)

    assert conn1.status == 200
    assert conn2.status == 200
    assert Jason.decode!(conn1.resp_body) == %{"n" => 1}
    assert Jason.decode!(conn2.resp_body) == %{"n" => 1}
  end