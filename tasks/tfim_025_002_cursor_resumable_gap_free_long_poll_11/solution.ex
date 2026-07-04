  test "multiple live pollers for the same user all receive the event",
       %{server: server, opts: opts} do
    t1 = Task.async(fn -> poll(opts, "user:1", 0) end)
    t2 = Task.async(fn -> poll(opts, "user:1", 0) end)

    Process.sleep(100)
    Notifications.publish(server, "user:1", %{"n" => 42})

    conn1 = Task.await(t1, 2_000)
    conn2 = Task.await(t2, 2_000)

    assert conn1.status == 200
    assert conn2.status == 200
    assert decode(conn1) == %{"cursor" => 1, "events" => [%{"n" => 42}]}
    assert decode(conn2) == %{"cursor" => 1, "events" => [%{"n" => 42}]}
  end