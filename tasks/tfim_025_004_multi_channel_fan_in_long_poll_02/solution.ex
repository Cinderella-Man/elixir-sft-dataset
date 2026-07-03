  test "returns a notification tagged with the channel it fired on", %{server: server, opts: opts} do
    task = Task.async(fn -> poll(opts, "user:1", ["orders", "alerts", "dm"]) end)
    Process.sleep(100)
    Notifications.publish(server, "user:1", "alerts", %{"level" => "high"})

    conn = Task.await(task, 2_000)
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> hd() =~ "application/json"

    body = Jason.decode!(conn.resp_body)
    assert body["channel"] == "alerts"
    assert body["payload"] == %{"level" => "high"}
  end