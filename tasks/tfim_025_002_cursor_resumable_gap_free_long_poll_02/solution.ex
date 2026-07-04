  test "an event published BEFORE the poll is not missed (replayed from buffer)",
       %{server: server, opts: opts} do
    # Nobody is connected yet.
    assert {:ok, 1} = Notifications.publish(server, "user:1", %{"body" => "early"})

    # Now the client polls from the beginning — a naive long poll would block
    # and eventually 204, losing the event. This one replays it immediately.
    conn = poll(opts, "user:1", 0)

    assert conn.status == 200
    assert hd(get_resp_header(conn, "content-type")) =~ "application/json"
    assert decode(conn) == %{"cursor" => 1, "events" => [%{"body" => "early"}]}
    assert cursor_header(conn) == ["1"]
  end