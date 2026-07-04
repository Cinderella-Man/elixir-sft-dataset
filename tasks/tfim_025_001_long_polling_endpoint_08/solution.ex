  test "poll returns only the first notification even if multiple arrive", %{server: server, opts: opts} do
    task = Task.async(fn -> poll(opts, "user:1") end)

    Process.sleep(100)

    Notifications.publish(server, "user:1", %{"seq" => 1})
    Notifications.publish(server, "user:1", %{"seq" => 2})

    conn = Task.await(task, 2_000)

    assert conn.status == 200
    assert Jason.decode!(conn.resp_body) == %{"seq" => 1}
  end