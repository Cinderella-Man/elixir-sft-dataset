# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Notifications do
  @moduledoc """
  In-memory pub/sub keyed per `(user_id, channel)` pair, backed by a `Registry`
  in `:duplicate` mode. Subscribers receive `{:notification, channel, payload}`
  messages, so a single process listening on several channels can tell which one
  fired.
  """

  @typedoc "How the backing `Registry` is referenced (its registered name)."
  @type server :: atom()

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

  @doc "Subscribes the calling process to notifications on `(user_id, channel)`."
  @spec subscribe(server(), term(), term()) :: :ok
  def subscribe(server \\ __MODULE__, user_id, channel) do
    {:ok, _pid} = Registry.register(server, {user_id, channel}, nil)
    :ok
  end

  @doc "Publishes `payload` to every process subscribed to `(user_id, channel)`."
  @spec publish(server(), term(), term(), term()) :: :ok
  def publish(server \\ __MODULE__, user_id, channel, payload) do
    Registry.dispatch(server, {user_id, channel}, fn entries ->
      for {pid, _value} <- entries, do: send(pid, {:notification, channel, payload})
    end)

    :ok
  end
end

defmodule NotificationPoller do
  @moduledoc """
  A Plug implementing `GET /api/notifications/poll` with multi-channel fan-in
  long polling: it subscribes to every requested `(user_id, channel)` pair and
  blocks on a single `receive` until the first notification arrives on any
  channel, returning it tagged with the channel that fired.
  """

  import Plug.Conn

  @default_timeout_ms 30_000

  @doc "Plug callback; returns the options unchanged."
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @doc """
  Plug callback that performs the multi-channel long poll and sends the
  response (200 with the fired notification, 204 on timeout, 401 without a
  user, or 400 without channels).
  """
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    server = Keyword.fetch!(opts, :notifications_server)
    timeout = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    conn = fetch_query_params(conn)

    case conn.assigns[:user_id] do
      nil ->
        send_resp(conn, 401, "unauthorized")

      user_id ->
        case parse_channels(conn.query_params["channels"]) do
          [] ->
            send_resp(conn, 400, "no channels")

          channels ->
            for channel <- channels, do: Notifications.subscribe(server, user_id, channel)
            wait_for_notification(conn, timeout)
        end
    end
  end

  @spec wait_for_notification(Plug.Conn.t(), non_neg_integer()) :: Plug.Conn.t()
  defp wait_for_notification(conn, timeout) do
    receive do
      {:notification, channel, payload} ->
        body = Jason.encode!(%{"channel" => channel, "payload" => payload})

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, body)
    after
      timeout ->
        send_resp(conn, 204, "")
    end
  end

  @spec parse_channels(String.t() | nil) :: [String.t()]
  defp parse_channels(nil), do: []
  defp parse_channels(str), do: String.split(str, ",", trim: true)
end

defmodule NotificationRouter do
  @moduledoc """
  Thin `Plug.Router` that forwards `GET /api/notifications/poll` to
  `NotificationPoller`, passing through `:notifications_server` and `:timeout_ms`,
  and returns 404 for everything else.
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
```

## Test harness — implement the `# TODO` test

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
    # TODO
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
```
