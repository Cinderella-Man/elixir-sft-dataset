  test "per-user sequences are independent", %{server: server, opts: opts} do
    assert {:ok, 1} = Notifications.publish(server, "user:a", %{"x" => "a1"})
    assert {:ok, 1} = Notifications.publish(server, "user:b", %{"x" => "b1"})
    assert {:ok, 2} = Notifications.publish(server, "user:a", %{"x" => "a2"})

    conn_a = poll(opts, "user:a", 0)
    conn_b = poll(opts, "user:b", 0)

    assert decode(conn_a) == %{"cursor" => 2, "events" => [%{"x" => "a1"}, %{"x" => "a2"}]}
    assert decode(conn_b) == %{"cursor" => 1, "events" => [%{"x" => "b1"}]}
  end