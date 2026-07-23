# One test is missing its body

Module plus harness below; a single `test` body was replaced with
`# TODO`. Reconstruct it from its name and the surrounding suite so the
harness passes for a correct implementation of the module. Touch nothing
else.

## Module under test

```elixir
defmodule Notifications do
  @moduledoc """
  In-memory pub/sub for user notifications backed by a `Registry` in
  `:duplicate` mode. Subscribers receive `{:notification, payload}` messages.
  """

  @doc """
  Starts the backing `Registry`. Accepts a `:name` option (default
  `Notifications`) used both for registration and as the server reference.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
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

  plug(:match)
  plug(:dispatch)

  get "/api/notifications/poll" do
    opts = conn.assigns.poller_opts
    NotificationPoller.call(conn, NotificationPoller.init(opts))
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end
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

  test "returns a notification published mid-poll", %{server: server, opts: opts} do
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
  # Default timeout when :timeout_ms is not supplied
  # -------------------------------------------------------

  test "omitting :timeout_ms keeps the connection open far past a short timeout",
       %{server: server, opts: opts} do
    default_opts = Keyword.delete(opts, :timeout_ms)
    user_id = "user:default-timeout"
    parent = self()

    {pid, ref} =
      spawn_monitor(fn -> send(parent, {:poll_result, poll(default_opts, user_id)}) end)

    # With no :timeout_ms the documented 30_000ms default applies, so the poll
    # must still be blocked (no 204 yet) long after any short timeout would fire.
    refute_receive {:poll_result, _}, 1_500

    # Still subscribed: a notification published this late is delivered as 200.
    Notifications.publish(server, user_id, %{"late" => true})

    assert_receive {:poll_result, conn}, 2_000
    assert conn.status == 200
    assert Jason.decode!(conn.resp_body) == %{"late" => true}

    Process.demonitor(ref, [:flush])
    Process.exit(pid, :kill)
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

  test "401 response carries the unauthorized body", %{opts: opts} do
    conn =
      :get
      |> conn("/api/notifications/poll")
      |> NotificationRouter.call(NotificationRouter.init(opts))

    assert conn.status == 401
    assert conn.resp_body == "unauthorized"
  end

  # -------------------------------------------------------
  # User isolation
  # -------------------------------------------------------

  test "user A notification not delivered to user B", %{server: server, opts: opts} do
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

  test "delivers to the correct user among many pollers", %{server: server, opts: opts} do
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

  test "all pollers for one user receive it", %{server: server, opts: opts} do
    # TODO
  end

  # -------------------------------------------------------
  # Only the first notification is returned (single shot)
  # -------------------------------------------------------

  test "poll returns only the first of several", %{server: server, opts: opts} do
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
