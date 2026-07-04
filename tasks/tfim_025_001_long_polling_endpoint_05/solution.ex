  test "notification for user A is not delivered to user B's poll", %{server: server, opts: opts} do
    # User B starts polling
    task_b =
      Task.async(fn ->
        poll(opts, "user:b")
      end)

    Process.sleep(100)

    # Publish only to user A
    Notifications.publish(server, "user:a", %{"for" => "a"})

    # User B should time out with 204
    conn_b = Task.await(task_b, 2_000)
    assert conn_b.status == 204
  end