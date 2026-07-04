  test "handles various JSON-serialisable payloads", %{server: server, opts: opts} do
    payloads = [
      %{"simple" => true},
      %{"nested" => %{"a" => [1, 2, 3]}},
      %{"unicode" => "héllo 🌍"}
    ]

    for payload <- payloads do
      task = Task.async(fn -> poll(opts, "user:1") end)
      Process.sleep(100)
      Notifications.publish(server, "user:1", payload)

      conn = Task.await(task, 2_000)
      assert conn.status == 200
      assert Jason.decode!(conn.resp_body) == payload
    end
  end