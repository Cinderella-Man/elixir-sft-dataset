  test "poll without :timeout_ms keeps holding the connection open", %{server: server} do
    opts = [notifications_server: server]
    task = Task.async(fn -> poll(opts, "user:default", ["orders"]) end)

    # The documented default is 30_000 ms, so the poll must still be pending
    # well past the 500 ms the other tests configure explicitly.
    assert Task.yield(task, 1_000) == nil

    conn = publish_until_answered(task, server, "user:default", "orders", %{"held" => true})
    assert conn.status == 200

    body = Jason.decode!(conn.resp_body)
    assert body["channel"] == "orders"
    assert body["payload"] == %{"held" => true}
  end