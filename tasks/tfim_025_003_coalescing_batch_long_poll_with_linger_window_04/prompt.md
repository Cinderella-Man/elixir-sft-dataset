# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Notifications do
  @moduledoc """
  In-memory pub/sub for user notifications backed by a `Registry` in
  `:duplicate` mode. Subscribers receive `{:notification, payload}` messages.
  """

  @typedoc "A server reference: the registered name or pid of the backing `Registry`."
  @type server :: atom() | pid()

  @doc """
  Starts the backing `Registry`. Accepts a `:name` option (default
  `Notifications`) used both for registration and as the server reference.
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Registry.start_link(keys: :duplicate, name: name)
  end

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @doc "Subscribes the calling process to notifications for `user_id`."
  @spec subscribe(server(), term()) :: :ok
  def subscribe(server \\ __MODULE__, user_id) do
    {:ok, _pid} = Registry.register(server, user_id, nil)
    :ok
  end

  @doc "Publishes `payload` to every process currently subscribed to `user_id`."
  @spec publish(server(), term(), term()) :: :ok
  def publish(server \\ __MODULE__, user_id, payload) do
    Registry.dispatch(server, user_id, fn entries ->
      for {pid, _value} <- entries, do: send(pid, {:notification, payload})
    end)

    :ok
  end
end

defmodule NotificationPoller do
  @moduledoc """
  A Plug implementing `GET /api/notifications/poll` with coalescing long
  polling: it blocks for the first notification, then keeps draining additional
  notifications for a short linger window and returns the whole burst as one
  batched JSON response.
  """

  import Plug.Conn

  @default_timeout_ms 30_000
  @default_linger_ms 50

  @doc "Plug callback. Returns the options unchanged."
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @doc """
  Plug callback. Subscribes the caller to notifications for
  `conn.assigns.user_id`, then coalesces a burst into one batched response.
  Returns 401 when the user id is missing and 204 when the timeout expires.
  """
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    server = Keyword.fetch!(opts, :notifications_server)
    timeout = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    linger = Keyword.get(opts, :linger_ms, @default_linger_ms)

    case conn.assigns[:user_id] do
      nil ->
        send_resp(conn, 401, "unauthorized")

      user_id ->
        Notifications.subscribe(server, user_id)
        wait_for_batch(conn, timeout, linger)
    end
  end

  @spec wait_for_batch(Plug.Conn.t(), non_neg_integer(), non_neg_integer()) :: Plug.Conn.t()
  defp wait_for_batch(conn, timeout, linger) do
    receive do
      {:notification, payload} ->
        batch = drain([payload], linger)
        respond(conn, batch)
    after
      timeout ->
        send_resp(conn, 204, "")
    end
  end

  @spec drain([term()], non_neg_integer()) :: [term()]
  defp drain(acc, linger) do
    receive do
      {:notification, payload} -> drain([payload | acc], linger)
    after
      linger -> Enum.reverse(acc)
    end
  end

  @spec respond(Plug.Conn.t(), [term()]) :: Plug.Conn.t()
  defp respond(conn, payloads) do
    body = Jason.encode!(%{"notifications" => payloads, "count" => length(payloads)})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, body)
  end
end

defmodule NotificationRouter do
  @moduledoc """
  Thin `Plug.Router` that forwards `GET /api/notifications/poll` to
  `NotificationPoller`, passing through `:notifications_server`, `:timeout_ms`,
  and `:linger_ms`, and returns 404 for everything else.
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
    # TODO
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
```
