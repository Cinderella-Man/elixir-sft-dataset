  test "204 on timeout echoes the request cursor so the client can resume",
       %{server: server, opts: opts} do
    # Advance the cursor to 2, then poll from 2 with nothing new.
    Notifications.publish(server, "user:1", %{"n" => 1})
    Notifications.publish(server, "user:1", %{"n" => 2})

    conn = poll(opts, "user:1", 2)

    assert conn.status == 204
    assert conn.resp_body == ""
    assert cursor_header(conn) == ["2"]
  end