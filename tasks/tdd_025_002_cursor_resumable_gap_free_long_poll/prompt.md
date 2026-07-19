# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule CursorLongPollTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  # -------------------------------------------------------
  # Setup — a fresh sequenced Notifications server per test
  # -------------------------------------------------------

  setup do
    server = :"notifications_#{System.unique_integer([:positive])}"
    start_supervised!({Notifications, name: server})

    opts = [
      notifications_server: server,
      timeout_ms: 500
    ]

    %{server: server, opts: opts}
  end

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  defp poll(opts, user_id, since) do
    :get
    |> conn("/api/notifications/poll?since=#{since}")
    |> assign(:user_id, user_id)
    |> NotificationRouter.call(NotificationRouter.init(opts))
  end

  defp decode(conn), do: Jason.decode!(conn.resp_body)

  defp cursor_header(conn), do: get_resp_header(conn, "x-notification-cursor")

  # -------------------------------------------------------
  # Gap-free semantics — the whole point of this variant
  # -------------------------------------------------------

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

  test "multiple buffered events replay in order with the highest cursor",
       %{server: server, opts: opts} do
    assert {:ok, 1} = Notifications.publish(server, "user:1", %{"n" => 1})
    assert {:ok, 2} = Notifications.publish(server, "user:1", %{"n" => 2})
    assert {:ok, 3} = Notifications.publish(server, "user:1", %{"n" => 3})

    conn = poll(opts, "user:1", 0)

    assert conn.status == 200

    assert decode(conn) == %{
             "cursor" => 3,
             "events" => [%{"n" => 1}, %{"n" => 2}, %{"n" => 3}]
           }

    assert cursor_header(conn) == ["3"]
  end

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

  # -------------------------------------------------------
  # Live blocking delivery
  # -------------------------------------------------------

  test "blocks and returns a notification that arrives during the poll",
       %{server: server, opts: opts} do
    task = Task.async(fn -> poll(opts, "user:1", 0) end)

    Process.sleep(100)
    Notifications.publish(server, "user:1", %{"live" => true})

    conn = Task.await(task, 2_000)
    assert conn.status == 200
    assert decode(conn) == %{"cursor" => 1, "events" => [%{"live" => true}]}
    assert cursor_header(conn) == ["1"]
  end

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

  # -------------------------------------------------------
  # Cursor parsing robustness
  # -------------------------------------------------------

  test "missing / garbage / negative since is treated as 0", %{server: server, opts: opts} do
    Notifications.publish(server, "user:1", %{"n" => 1})

    for since <- ["", "abc", "-5", "not_a_number"] do
      conn =
        :get
        |> conn("/api/notifications/poll?since=#{since}")
        |> assign(:user_id, "user:1")
        |> NotificationRouter.call(NotificationRouter.init(opts))

      assert conn.status == 200
      assert decode(conn)["events"] == [%{"n" => 1}]
    end
  end

  # -------------------------------------------------------
  # Auth
  # -------------------------------------------------------

  test "401 when user_id is absent", %{opts: opts} do
    conn =
      :get
      |> conn("/api/notifications/poll?since=0")
      |> NotificationRouter.call(NotificationRouter.init(opts))

    assert conn.status == 401
    assert conn.resp_body == "unauthorized"
  end

  # -------------------------------------------------------
  # User isolation
  # -------------------------------------------------------

  test "events for user A do not leak to user B", %{server: server, opts: opts} do
    task_b = Task.async(fn -> poll(opts, "user:b", 0) end)

    Process.sleep(100)
    Notifications.publish(server, "user:a", %{"for" => "a"})

    conn_b = Task.await(task_b, 2_000)
    assert conn_b.status == 204
    assert cursor_header(conn_b) == ["0"]
  end

  test "per-user sequences are independent", %{server: server, opts: opts} do
    assert {:ok, 1} = Notifications.publish(server, "user:a", %{"x" => "a1"})
    assert {:ok, 1} = Notifications.publish(server, "user:b", %{"x" => "b1"})
    assert {:ok, 2} = Notifications.publish(server, "user:a", %{"x" => "a2"})

    conn_a = poll(opts, "user:a", 0)
    conn_b = poll(opts, "user:b", 0)

    assert decode(conn_a) == %{"cursor" => 2, "events" => [%{"x" => "a1"}, %{"x" => "a2"}]}
    assert decode(conn_b) == %{"cursor" => 1, "events" => [%{"x" => "b1"}]}
  end

  # -------------------------------------------------------
  # Fan-out to multiple live pollers
  # -------------------------------------------------------

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

  # -------------------------------------------------------
  # Buffer eviction
  # -------------------------------------------------------

  test "buffer retains only the most recent :buffer_size events" do
    server = :"notifications_#{System.unique_integer([:positive])}"
    start_supervised!({Notifications, name: server, buffer_size: 3})

    for n <- 1..5, do: Notifications.publish(server, "user:1", %{"n" => n})

    # Only seqs 3,4,5 survive; asking since 0 still returns them oldest-first.
    events = Notifications.events_since(server, "user:1", 0)
    assert events == [{3, %{"n" => 3}}, {4, %{"n" => 4}}, {5, %{"n" => 5}}]
  end

  # -------------------------------------------------------
  # Router
  # -------------------------------------------------------

  test "router returns 404 for unknown paths", %{opts: opts} do
    conn =
      :get
      |> conn("/api/unknown")
      |> NotificationRouter.call(NotificationRouter.init(opts))

    assert conn.status == 404
  end

  # -------------------------------------------------------
  # Notifications unit tests
  # -------------------------------------------------------

  test "publish assigns monotonic sequences and delivers with seq", %{server: server} do
    Notifications.subscribe(server, "user:direct")

    assert {:ok, 1} = Notifications.publish(server, "user:direct", %{"a" => 1})
    assert {:ok, 2} = Notifications.publish(server, "user:direct", %{"a" => 2})

    assert_receive {:notification, 1, %{"a" => 1}}, 500
    assert_receive {:notification, 2, %{"a" => 2}}, 500
  end

  test "events_since filters strictly greater than cursor", %{server: server} do
    Notifications.publish(server, "user:1", %{"n" => 1})
    Notifications.publish(server, "user:1", %{"n" => 2})
    Notifications.publish(server, "user:1", %{"n" => 3})

    assert Notifications.events_since(server, "user:1", 0) ==
             [{1, %{"n" => 1}}, {2, %{"n" => 2}}, {3, %{"n" => 3}}]

    assert Notifications.events_since(server, "user:1", 2) == [{3, %{"n" => 3}}]
    assert Notifications.events_since(server, "user:1", 3) == []
  end

  test "publish to a user with no subscribers does not crash", %{server: server} do
    assert {:ok, 1} = Notifications.publish(server, "nobody", %{"ignored" => true})
  end

  test "dead subscribers are dropped and do not accumulate", %{server: server} do
    {:ok, agent} = Agent.start(fn -> :ok end)
    Agent.get(agent, fn _ -> Notifications.subscribe(server, "user:1") end)
    ref = Process.monitor(agent)
    Agent.stop(agent)
    assert_receive {:DOWN, ^ref, :process, ^agent, _}, 500

    # Publishing after the subscriber died must still succeed.
    assert {:ok, 1} = Notifications.publish(server, "user:1", %{"n" => 1})
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
