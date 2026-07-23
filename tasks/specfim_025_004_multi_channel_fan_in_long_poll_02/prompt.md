# Fill in one @spec

Below: a working module where the `@spec` for
`start_link/1` has been removed (see the `# TODO: @spec` marker).
Provide exactly that typespec, consistent with the implementation's
arguments, guards, and all reachable return shapes. No other edits.

## The module with the `@spec` for `start_link/1` missing

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
  # TODO: @spec
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

The `@spec` attribute only — nothing more.
