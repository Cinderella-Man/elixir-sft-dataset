Implement the public `call/2` Plug callback for the `NotificationPoller` module.

`call/2` receives the `Plug.Conn` and the keyword `opts` returned by `init/1`. It
should read three options from `opts`: `:notifications_server` (required — use
`Keyword.fetch!/2`), `:timeout_ms` (default `@default_timeout_ms`, i.e. `30_000`),
and `:linger_ms` (default `@default_linger_ms`, i.e. `50`). Then it must look up the
user id at `conn.assigns[:user_id]`. If the user id is missing (`nil`), respond with
status `401` and the body `"unauthorized"` using `send_resp/3` and return that conn.
Otherwise, subscribe the calling process to notifications for that user via
`Notifications.subscribe(server, user_id)`, then delegate to
`wait_for_batch(conn, timeout, linger)` to block for the first notification, coalesce
the burst, and produce the batched response.

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
    # TODO
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