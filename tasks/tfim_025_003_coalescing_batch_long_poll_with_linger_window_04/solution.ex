  test "preserves arrival order within a burst", %{server: server, opts: opts} do
    task = Task.async(fn -> poll(opts, "user:1") end)
    Process.sleep(100)

    for n <- 1..5, do: Notifications.publish(server, "user:1", %{"n" => n})

    conn = Task.await(task, 2_000)
    body = Jason.decode!(conn.resp_body)
    assert body["notifications"] == Enum.map(1..5, &%{"n" => &1})
    assert body["count"] == 5
  end