  test "coalesces a burst of notifications into one batched response", %{server: server, opts: opts} do
    task = Task.async(fn -> poll(opts, "user:1") end)
    Process.sleep(100)

    Notifications.publish(server, "user:1", %{"seq" => 1})
    Notifications.publish(server, "user:1", %{"seq" => 2})
    Notifications.publish(server, "user:1", %{"seq" => 3})

    conn = Task.await(task, 2_000)
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> hd() =~ "application/json"

    body = Jason.decode!(conn.resp_body)
    assert body["notifications"] == [%{"seq" => 1}, %{"seq" => 2}, %{"seq" => 3}]
    assert body["count"] == 3
  end