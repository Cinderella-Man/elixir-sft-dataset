  test "resuming from a cursor returns only newer events, no duplicates",
       %{server: server, opts: opts} do
    Notifications.publish(server, "user:1", %{"n" => 1})

    conn1 = poll(opts, "user:1", 0)
    assert conn1.status == 200
    assert decode(conn1)["cursor"] == 1
    assert decode(conn1)["events"] == [%{"n" => 1}]

    # More arrive; the client resumes from cursor 1.
    Notifications.publish(server, "user:1", %{"n" => 2})
    Notifications.publish(server, "user:1", %{"n" => 3})

    conn2 = poll(opts, "user:1", 1)
    assert conn2.status == 200
    assert decode(conn2) == %{"cursor" => 3, "events" => [%{"n" => 2}, %{"n" => 3}]}
  end