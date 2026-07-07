  test "all pollers for one user receive the full batch", %{server: server, opts: opts} do
    task1 = Task.async(fn -> poll(opts, "user:1") end)
    task2 = Task.async(fn -> poll(opts, "user:1") end)
    Process.sleep(100)

    Notifications.publish(server, "user:1", %{"n" => 1})
    Notifications.publish(server, "user:1", %{"n" => 2})

    conn1 = Task.await(task1, 2_000)
    conn2 = Task.await(task2, 2_000)

    assert Jason.decode!(conn1.resp_body)["notifications"] == [%{"n" => 1}, %{"n" => 2}]
    assert Jason.decode!(conn2.resp_body)["notifications"] == [%{"n" => 1}, %{"n" => 2}]
  end