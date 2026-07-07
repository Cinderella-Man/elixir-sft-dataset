  test "all pollers on one channel receive it", %{server: server, opts: opts} do
    task1 = Task.async(fn -> poll(opts, "user:1", ["x"]) end)
    task2 = Task.async(fn -> poll(opts, "user:1", ["x", "y"]) end)
    Process.sleep(100)

    Notifications.publish(server, "user:1", "x", %{"n" => 1})

    conn1 = Task.await(task1, 2_000)
    conn2 = Task.await(task2, 2_000)

    assert Jason.decode!(conn1.resp_body)["channel"] == "x"
    assert Jason.decode!(conn2.resp_body)["channel"] == "x"
  end