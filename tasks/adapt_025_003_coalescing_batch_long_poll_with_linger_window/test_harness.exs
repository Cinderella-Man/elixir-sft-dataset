defmodule CoalescingNotificationPollerTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  setup do
    server = :"notifications_#{System.unique_integer([:positive])}"
    start_supervised!({Notifications, name: server})

    opts = [
      notifications_server: server,
      timeout_ms: 500,
      linger_ms: 120
    ]

    %{server: server, opts: opts}
  end

  defp poll(opts, user_id) do
    :get
    |> conn("/api/notifications/poll")
    |> assign(:user_id, user_id)
    |> NotificationRouter.call(NotificationRouter.init(opts))
  end

  # -------------------------------------------------------
  # Coalescing — the defining feature
  # -------------------------------------------------------

  test "coalesces a burst into one batched response", %{server: server, opts: opts} do
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

  test "single notification returns a one-element batch", %{server: server, opts: opts} do
    task = Task.async(fn -> poll(opts, "user:1") end)
    Process.sleep(100)
    Notifications.publish(server, "user:1", %{"only" => true})

    conn = Task.await(task, 2_000)
    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert body["notifications"] == [%{"only" => true}]
    assert body["count"] == 1
  end

  test "preserves arrival order within a burst", %{server: server, opts: opts} do
    task = Task.async(fn -> poll(opts, "user:1") end)
    Process.sleep(100)

    for n <- 1..5, do: Notifications.publish(server, "user:1", %{"n" => n})

    conn = Task.await(task, 2_000)
    body = Jason.decode!(conn.resp_body)
    assert body["notifications"] == Enum.map(1..5, &%{"n" => &1})
    assert body["count"] == 5
  end

  test "returns 204 when timeout expires with no notifications", %{opts: opts} do
    conn = poll(opts, "user:1")
    assert conn.status == 204
    assert conn.resp_body == ""
  end

  # -------------------------------------------------------
  # Authentication
  # -------------------------------------------------------

  test "returns 401 when user_id is not in assigns", %{opts: opts} do
    conn =
      :get
      |> conn("/api/notifications/poll")
      |> NotificationRouter.call(NotificationRouter.init(opts))

    assert conn.status == 401
  end

  # -------------------------------------------------------
  # User isolation
  # -------------------------------------------------------

  test "a burst for user A is not delivered to user B", %{server: server, opts: opts} do
    task_b = Task.async(fn -> poll(opts, "user:b") end)
    Process.sleep(100)

    Notifications.publish(server, "user:a", %{"for" => "a"})
    Notifications.publish(server, "user:a", %{"for" => "a2"})

    conn_b = Task.await(task_b, 2_000)
    assert conn_b.status == 204
  end

  test "correct user receives their batch among many pollers", %{server: server, opts: opts} do
    task_a = Task.async(fn -> poll(opts, "user:a") end)
    task_b = Task.async(fn -> poll(opts, "user:b") end)
    Process.sleep(100)

    Notifications.publish(server, "user:b", %{"m" => 1})
    Notifications.publish(server, "user:b", %{"m" => 2})

    conn_b = Task.await(task_b, 2_000)
    assert conn_b.status == 200
    assert Jason.decode!(conn_b.resp_body)["count"] == 2

    conn_a = Task.await(task_a, 2_000)
    assert conn_a.status == 204
  end

  # -------------------------------------------------------
  # Multiple subscribers for the same user
  # -------------------------------------------------------

  test "all pollers for one user receive the full batch", %{server: server, opts: opts} do
    task1 = Task.async(fn -> poll(opts, "user:1") end)
    task2 = Task.async(fn -> poll(opts, "user:1") end)
    Process.sleep(100)

    Notifications.publish(server, "user:1", %{"n" => 1})
    Notifications.publish(server, "user:1", %{"n" => 2})

    conn1 = Task.await(task1, 2_000)
    conn2 = Task.await(task2, 2_000)

    assert Jason.decode!(conn1.resp_body)["notifications"] == [%{"n" => 1}, %{"n" => 2}]
    assert Jason.decode!(conn2.resp_body)["notifications"] == [%{"n" => 1}, %{"n" => 2}]
  end

  # -------------------------------------------------------
  # Payload variety
  # -------------------------------------------------------

  test "handles various JSON-serialisable payloads in a batch", %{server: server, opts: opts} do
    task = Task.async(fn -> poll(opts, "user:1") end)
    Process.sleep(100)

    Notifications.publish(server, "user:1", %{"nested" => %{"a" => [1, 2, 3]}})
    Notifications.publish(server, "user:1", %{"unicode" => "héllo 🌍"})

    conn = Task.await(task, 2_000)
    body = Jason.decode!(conn.resp_body)

    assert body["notifications"] == [
             %{"nested" => %{"a" => [1, 2, 3]}},
             %{"unicode" => "héllo 🌍"}
           ]
  end

  # -------------------------------------------------------
  # Router — 404
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

  test "subscribe and publish delivers message to calling process", %{server: server} do
    Notifications.subscribe(server, "user:direct")
    Notifications.publish(server, "user:direct", %{"direct" => true})
    assert_receive {:notification, %{"direct" => true}}, 500
  end

  test "publish to a user with no subscribers does not crash", %{server: server} do
    assert :ok = Notifications.publish(server, "nobody", %{"ignored" => true})
  end
end
