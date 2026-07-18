  test "linger_ms falls back to the documented default when the option is omitted",
       %{server: server} do
    opts = [notifications_server: server, timeout_ms: 500]
    task = Task.async(fn -> poll(opts, "user:dl") end)
    Process.sleep(100)

    Notifications.publish(server, "user:dl", %{"d" => 1})
    Notifications.publish(server, "user:dl", %{"d" => 2})

    # A default linger of 50ms must have closed long before this arrives.
    Process.sleep(250)
    Notifications.publish(server, "user:dl", %{"d" => 3})

    conn = Task.await(task, 2_000)
    assert conn.status == 200

    body = Jason.decode!(conn.resp_body)
    assert body["notifications"] == [%{"d" => 1}, %{"d" => 2}]
    assert body["count"] == 2
  end