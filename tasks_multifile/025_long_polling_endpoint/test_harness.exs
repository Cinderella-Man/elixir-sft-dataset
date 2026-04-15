defmodule NotificationPollerTest do
  use ExUnit.Case, async: false
  use Plug.Test

  # -------------------------------------------------------
  # Setup — start a fresh Notifications server per test
  # -------------------------------------------------------

  setup do
    server = :"notifications_#{System.unique_integer([:positive])}"
    start_supervised!({Notifications, name: server})

    opts = [
      notifications_server: server,
      timeout_ms: 500  # short timeout so tests run fast
    ]

    %{server: server, opts: opts}
  end

  # -------------------------------------------------------
  # Helper to invoke the router like a real HTTP request
  # -------------------------------------------------------

  defp poll(opts, user_id) do
    :get
    |> conn("/api/notifications/poll")
    |> assign(:user_id, user_id)
    |> NotificationRouter.call(NotificationRouter.init(opts))
  end

  # -------------------------------------------------------
  # Basic publish / receive
  # -------------------------------------------------------

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

  test "returns 204 when timeout expires with no notifications", %{opts: opts} do
    # Poll with the short 500ms timeout — nobody publishes anything
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

  test "notification reaches the correct user among multiple pollers", %{server: server, opts: opts} do
    task_a = Task.async(fn -> poll(opts, "user:a") end)
    task_b = Task.async(fn -> poll(opts, "user:b") end)

    Process.sleep(100)

    Notifications.publish(server, "user:b", %{"msg" => "for_b"})

    conn_b = Task.await(task_b, 2_000)
    assert conn_b.status == 200
    assert Jason.decode!(conn_b.resp_body) == %{"msg" => "for_b"}

    # User A should time out
    conn_a = Task.await(task_a, 2_000)
    assert conn_a.status == 204
  end

  # -------------------------------------------------------
  # Multiple subscribers for the same user
  # -------------------------------------------------------

  test "multiple pollers for the same user all receive the notification", %{server: server, opts: opts} do
    task1 = Task.async(fn -> poll(opts, "user:1") end)
    task2 = Task.async(fn -> poll(opts, "user:1") end)

    Process.sleep(100)

    Notifications.publish(server, "user:1", %{"n" => 1})

    conn1 = Task.await(task1, 2_000)
    conn2 = Task.await(task2, 2_000)

    assert conn1.status == 200
    assert conn2.status == 200
    assert Jason.decode!(conn1.resp_body) == %{"n" => 1}
    assert Jason.decode!(conn2.resp_body) == %{"n" => 1}
  end

  # -------------------------------------------------------
  # Only the first notification is returned (single shot)
  # -------------------------------------------------------

  test "poll returns only the first notification even if multiple arrive", %{server: server, opts: opts} do
    task = Task.async(fn -> poll(opts, "user:1") end)

    Process.sleep(100)

    Notifications.publish(server, "user:1", %{"seq" => 1})
    Notifications.publish(server, "user:1", %{"seq" => 2})

    conn = Task.await(task, 2_000)

    assert conn.status == 200
    assert Jason.decode!(conn.resp_body) == %{"seq" => 1}
  end

  # -------------------------------------------------------
  # Payload types
  # -------------------------------------------------------

  test "handles various JSON-serialisable payloads", %{server: server, opts: opts} do
    payloads = [
      %{"simple" => true},
      %{"nested" => %{"a" => [1, 2, 3]}},
      %{"unicode" => "héllo 🌍"}
    ]

    for payload <- payloads do
      task = Task.async(fn -> poll(opts, "user:1") end)
      Process.sleep(100)
      Notifications.publish(server, "user:1", payload)

      conn = Task.await(task, 2_000)
      assert conn.status == 200
      assert Jason.decode!(conn.resp_body) == payload
    end
  end

  # -------------------------------------------------------
  # Router — 404 for unknown routes
  # -------------------------------------------------------

  test "router returns 404 for unknown paths", %{opts: opts} do
    conn =
      :get
      |> conn("/api/unknown")
      |> NotificationRouter.call(NotificationRouter.init(opts))

    assert conn.status == 404
  end

  # -------------------------------------------------------
  # Notifications pub/sub unit tests
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
