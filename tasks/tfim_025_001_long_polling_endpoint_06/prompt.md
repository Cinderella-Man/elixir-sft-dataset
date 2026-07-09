# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
<file path="lib/notifications.ex">
defmodule Notifications do
  @moduledoc """
  In-memory pub/sub for user notifications backed by a `Registry` in
  `:duplicate` mode. Subscribers receive `{:notification, payload}` messages.
  """

  @doc """
  Starts the backing `Registry`. Accepts a `:name` option (default
  `Notifications`) used both for registration and as the server reference.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Registry.start_link(keys: :duplicate, name: name)
  end

  @doc false
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @doc """
  Subscribes the calling process to notifications for `user_id`.
  """
  def subscribe(server \\ __MODULE__, user_id) do
    {:ok, _pid} = Registry.register(server, user_id, nil)
    :ok
  end

  @doc """
  Publishes `payload` to every process currently subscribed to `user_id`.
  """
  def publish(server \\ __MODULE__, user_id, payload) do
    Registry.dispatch(server, user_id, fn entries ->
      for {pid, _value} <- entries, do: send(pid, {:notification, payload})
    end)

    :ok
  end
end

defmodule NotificationPoller do
  @moduledoc """
  A Plug implementing `GET /api/notifications/poll` using true long-polling: it
  subscribes to `Notifications` for the authenticated user and blocks on a
  `receive` until a notification arrives or the timeout elapses.
  """

  import Plug.Conn

  @default_timeout_ms 30_000

  def init(opts), do: opts

  def call(conn, opts) do
    server = Keyword.fetch!(opts, :notifications_server)
    timeout = Keyword.get(opts, :timeout_ms, @default_timeout_ms)

    case conn.assigns[:user_id] do
      nil ->
        send_resp(conn, 401, "unauthorized")

      user_id ->
        Notifications.subscribe(server, user_id)
        wait_for_notification(conn, timeout)
    end
  end

  defp wait_for_notification(conn, timeout) do
    receive do
      {:notification, payload} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(payload))
    after
      timeout ->
        send_resp(conn, 204, "")
    end
  end
end

defmodule NotificationRouter do
  @moduledoc """
  Thin `Plug.Router` that forwards `GET /api/notifications/poll` to
  `NotificationPoller`, passing through the `:notifications_server` and
  `:timeout_ms` options, and returns 404 for everything else.
  """

  use Plug.Router, copy_opts_to_assign: :poller_opts

  plug :match
  plug :dispatch

  get "/api/notifications/poll" do
    opts = conn.assigns.poller_opts
    NotificationPoller.call(conn, NotificationPoller.init(opts))
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end
</file>
```

## Test harness — implement the `# TODO` test

```elixir
defmodule NotificationPollerTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  # -------------------------------------------------------
  # Setup — start a fresh Notifications server per test
  # -------------------------------------------------------

  setup do
    server = :"notifications_#{System.unique_integer([:positive])}"
    start_supervised!({Notifications, name: server})

    opts = [
      notifications_server: server,
      # short timeout so tests run fast
      timeout_ms: 500
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

  test "returns notification immediately when one is published during poll", %{
    server: server,
    opts: opts
  } do
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

  test "notification reaches the correct user among multiple pollers", %{
    server: server,
    opts: opts
  } do
    # TODO
  end

  # -------------------------------------------------------
  # Multiple subscribers for the same user
  # -------------------------------------------------------

  test "multiple pollers for the same user all receive the notification", %{
    server: server,
    opts: opts
  } do
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

  test "poll returns only the first notification even if multiple arrive", %{
    server: server,
    opts: opts
  } do
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
```
