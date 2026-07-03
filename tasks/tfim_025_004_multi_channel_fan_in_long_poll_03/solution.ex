  test "returns the first notification among several channels", %{server: server, opts: opts} do
    task = Task.async(fn -> poll(opts, "user:1", ["a", "b"]) end)
    Process.sleep(100)
    Notifications.publish(server, "user:1", "b", %{"first" => true})
    Notifications.publish(server, "user:1", "a", %{"second" => true})

    conn = Task.await(task, 2_000)
    body = Jason.decode!(conn.resp_body)
    assert body["channel"] == "b"
    assert body["payload"] == %{"first" => true}
  end