# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule MultiChannelNotificationPollerTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  setup do
    server = :"notifications_#{System.unique_integer([:positive])}"
    start_supervised!({Notifications, name: server})

    opts = [
      notifications_server: server,
      timeout_ms: 500
    ]

    %{server: server, opts: opts}
  end

  defp poll(opts, user_id, channels) do
    :get
    |> conn("/api/notifications/poll?channels=#{Enum.join(channels, ",")}")
    |> assign(:user_id, user_id)
    |> NotificationRouter.call(NotificationRouter.init(opts))
  end

  # -------------------------------------------------------
  # Fan-in across channels — the defining feature
  # -------------------------------------------------------

  test "notification is tagged with its channel", %{server: server, opts: opts} do
    task = Task.async(fn -> poll(opts, "user:1", ["orders", "alerts", "dm"]) end)
    Process.sleep(100)
    Notifications.publish(server, "user:1", "alerts", %{"level" => "high"})

    conn = Task.await(task, 2_000)
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> hd() =~ "application/json"

    body = Jason.decode!(conn.resp_body)
    assert body["channel"] == "alerts"
    assert body["payload"] == %{"level" => "high"}
  end

  test "returns the first notification among several channels", %{server: server, opts: opts} do
    task = Task.async(fn -> poll(opts, "user:1", ["a", "b"]) end)
    Process.sleep(100)
    Notifications.publish(server, "user:1", "b", %{"first" => true})
    Notifications.publish(server, "user:1", "a", %{"second" => true})

    conn = Task.await(task, 2_000)
    body = Jason.decode!(conn.resp_body)
    assert body["channel"] == "b"
    assert body["payload"] == %{"first" => true}
  end

  test "publish to an unsubscribed channel doesn't wake poll", %{server: server, opts: opts} do
    task = Task.async(fn -> poll(opts, "user:1", ["a", "b"]) end)
    Process.sleep(100)
    Notifications.publish(server, "user:1", "c", %{"ignored" => true})

    conn = Task.await(task, 2_000)
    assert conn.status == 204
  end

  test "returns 204 when timeout expires with no notification", %{opts: opts} do
    conn = poll(opts, "user:1", ["a"])
    assert conn.status == 204
    assert conn.resp_body == ""
  end

  # -------------------------------------------------------
  # Authentication & channel validation
  # -------------------------------------------------------

  test "returns 401 when user_id is not in assigns", %{opts: opts} do
    conn =
      :get
      |> conn("/api/notifications/poll?channels=a")
      |> NotificationRouter.call(NotificationRouter.init(opts))

    assert conn.status == 401
  end

  test "returns 400 when channels param is missing", %{opts: opts} do
    conn =
      :get
      |> conn("/api/notifications/poll")
      |> assign(:user_id, "user:1")
      |> NotificationRouter.call(NotificationRouter.init(opts))

    assert conn.status == 400
    assert conn.resp_body == "no channels"
  end

  test "returns 400 when channels param is empty", %{opts: opts} do
    conn =
      :get
      |> conn("/api/notifications/poll?channels=")
      |> assign(:user_id, "user:1")
      |> NotificationRouter.call(NotificationRouter.init(opts))

    assert conn.status == 400
  end

  # -------------------------------------------------------
  # User isolation
  # -------------------------------------------------------

  test "same channel name is isolated per user", %{server: server, opts: opts} do
    task_b = Task.async(fn -> poll(opts, "user:b", ["shared"]) end)
    Process.sleep(100)
    Notifications.publish(server, "user:a", "shared", %{"for" => "a"})

    conn_b = Task.await(task_b, 2_000)
    assert conn_b.status == 204
  end

  test "notification reaches only the subscribed user", %{server: server, opts: opts} do
    task_a = Task.async(fn -> poll(opts, "user:a", ["chan"]) end)
    task_b = Task.async(fn -> poll(opts, "user:b", ["chan"]) end)
    Process.sleep(100)

    Notifications.publish(server, "user:b", "chan", %{"msg" => "for_b"})

    conn_b = Task.await(task_b, 2_000)
    assert conn_b.status == 200
    assert Jason.decode!(conn_b.resp_body)["payload"] == %{"msg" => "for_b"}

    conn_a = Task.await(task_a, 2_000)
    assert conn_a.status == 204
  end

  # -------------------------------------------------------
  # Multiple subscribers on the same channel
  # -------------------------------------------------------

  test "all pollers on one channel receive it", %{server: server, opts: opts} do
    task1 = Task.async(fn -> poll(opts, "user:1", ["x"]) end)
    task2 = Task.async(fn -> poll(opts, "user:1", ["x", "y"]) end)
    Process.sleep(100)

    Notifications.publish(server, "user:1", "x", %{"n" => 1})

    conn1 = Task.await(task1, 2_000)
    conn2 = Task.await(task2, 2_000)

    assert Jason.decode!(conn1.resp_body)["channel"] == "x"
    assert Jason.decode!(conn2.resp_body)["channel"] == "x"
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

  test "subscribe and publish delivers a channel-tagged message", %{server: server} do
    Notifications.subscribe(server, "user:direct", "chan")
    Notifications.publish(server, "user:direct", "chan", %{"direct" => true})
    assert_receive {:notification, "chan", %{"direct" => true}}, 500
  end

  test "publish with no subscribers does not crash", %{server: server} do
    assert :ok = Notifications.publish(server, "nobody", "chan", %{"ignored" => true})
  end

  # -------------------------------------------------------
  # Default :timeout_ms — the option may be omitted entirely
  # -------------------------------------------------------

  # Republishes until the in-flight poll answers, so no wall-clock sleep is
  # needed to line the publish up with the poller's subscription.
  defp publish_until_answered(task, server, user_id, channel, payload, attempts \\ 40) do
    case Task.yield(task, 50) do
      {:ok, conn} ->
        conn

      nil when attempts > 0 ->
        Notifications.publish(server, user_id, channel, payload)
        publish_until_answered(task, server, user_id, channel, payload, attempts - 1)

      _ ->
        flunk("long poll never answered while notifications were being published")
    end
  end

  test "poll without :timeout_ms keeps holding the connection open", %{server: server} do
    opts = [notifications_server: server]
    task = Task.async(fn -> poll(opts, "user:default", ["orders"]) end)

    # The documented default is 30_000 ms, so the poll must still be pending
    # well past the 500 ms the other tests configure explicitly.
    assert Task.yield(task, 1_000) == nil

    conn = publish_until_answered(task, server, "user:default", "orders", %{"held" => true})
    assert conn.status == 200

    body = Jason.decode!(conn.resp_body)
    assert body["channel"] == "orders"
    assert body["payload"] == %{"held" => true}
  end

  test "poll without :timeout_ms still validates channels", %{server: server} do
    conn =
      :get
      |> conn("/api/notifications/poll")
      |> assign(:user_id, "user:default")
      |> NotificationRouter.call(NotificationRouter.init(notifications_server: server))

    assert conn.status == 400
    assert conn.resp_body == "no channels"
  end

  # -------------------------------------------------------
  # Response bodies for the error paths
  # -------------------------------------------------------

  test "401 response carries the unauthorized body", %{opts: opts} do
    conn =
      :get
      |> conn("/api/notifications/poll?channels=a")
      |> NotificationRouter.call(NotificationRouter.init(opts))

    assert conn.status == 401
    assert conn.resp_body == "unauthorized"
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
