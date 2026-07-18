  test "linger window extends past the original deadline while a burst keeps arriving",
       %{server: server, opts: opts} do
    task = Task.async(fn -> poll(opts, "user:slide") end)
    Process.sleep(100)

    # linger_ms is 120: each gap is under the window, but the total span (160ms)
    # is well past the deadline measured from the FIRST notification.
    Notifications.publish(server, "user:slide", %{"seq" => 1})
    Process.sleep(80)
    Notifications.publish(server, "user:slide", %{"seq" => 2})
    Process.sleep(80)
    Notifications.publish(server, "user:slide", %{"seq" => 3})

    conn = Task.await(task, 2_000)
    assert conn.status == 200

    body = Jason.decode!(conn.resp_body)
    assert body["notifications"] == [%{"seq" => 1}, %{"seq" => 2}, %{"seq" => 3}]
    assert body["count"] == 3
  end