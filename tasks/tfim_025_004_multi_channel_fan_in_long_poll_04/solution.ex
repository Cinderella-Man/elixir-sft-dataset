  test "publish to an unsubscribed channel doesn't wake poll", %{server: server, opts: opts} do
    task = Task.async(fn -> poll(opts, "user:1", ["a", "b"]) end)
    Process.sleep(100)
    Notifications.publish(server, "user:1", "c", %{"ignored" => true})

    conn = Task.await(task, 2_000)
    assert conn.status == 204
  end