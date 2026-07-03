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

  test "returns a notification tagged with the channel it fired on", %{server: server, opts: opts} do
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

  test "a publish to an unsubscribed channel does not wake the poll", %{server: server, opts: opts} do
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

  test "multiple pollers on the same channel all receive the notification", %{server: server, opts: opts} do
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
end