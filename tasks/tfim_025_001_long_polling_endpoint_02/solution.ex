  test "returns notification immediately when one is published during poll", %{server: server, opts: opts} do
    payload = %{"type" => "message", "body" => "hello"}

    # Start the long-poll in a background task
    task =
      Task.async(fn ->
        poll(opts, "user:1")
      end)

    # Give the poll a moment to subscribe, then publish
    Process.sleep(100)
    Notifications.publish(server, "user:1", payload)

    conn = Task.await(task, 2_000)

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> hd() =~ "application/json"
    assert Jason.decode!(conn.resp_body) == payload
  end