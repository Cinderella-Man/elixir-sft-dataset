Implement the public `call/2` Plug callback for `NotificationPoller`. It receives a
`Plug.Conn` and the initialized options keyword list, and must perform the
multi-channel fan-in long poll before sending a response.

It should:

- Read the notifications server from the options with `Keyword.fetch!(opts, :notifications_server)`.
- Read the timeout from the options with `Keyword.get(opts, :timeout_ms, @default_timeout_ms)`.
- Ensure the query params are loaded by calling `fetch_query_params/1` on `conn`.
- Look at `conn.assigns[:user_id]`:
  - If it is `nil`, respond 401 with body `"unauthorized"` via `send_resp/3`.
  - Otherwise, parse the requested channels from `conn.query_params["channels"]`
    using the private `parse_channels/1` helper:
    - If the result is an empty list, respond 400 with body `"no channels"`.
    - Otherwise, subscribe the calling process to `(user_id, channel)` for **each**
      requested channel via `Notifications.subscribe(server, user_id, channel)`, then
      block for the first notification by delegating to `wait_for_notification(conn, timeout)`
      and returning its result.

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
    # TODO
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