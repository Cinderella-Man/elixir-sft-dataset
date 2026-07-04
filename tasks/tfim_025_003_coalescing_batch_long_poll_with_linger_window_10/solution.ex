  test "handles various JSON-serialisable payloads in a batch", %{server: server, opts: opts} do
    task = Task.async(fn -> poll(opts, "user:1") end)
    Process.sleep(100)

    Notifications.publish(server, "user:1", %{"nested" => %{"a" => [1, 2, 3]}})
    Notifications.publish(server, "user:1", %{"unicode" => "héllo 🌍"})

    conn = Task.await(task, 2_000)
    body = Jason.decode!(conn.resp_body)
    assert body["notifications"] == [%{"nested" => %{"a" => [1, 2, 3]}}, %{"unicode" => "héllo 🌍"}]
  end