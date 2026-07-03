  test "a single notification is returned as a one-element batch", %{server: server, opts: opts} do
    task = Task.async(fn -> poll(opts, "user:1") end)
    Process.sleep(100)
    Notifications.publish(server, "user:1", %{"only" => true})

    conn = Task.await(task, 2_000)
    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert body["notifications"] == [%{"only" => true}]
    assert body["count"] == 1
  end