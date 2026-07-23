# Write tests for this module

Below is a completed Elixir module and the original specification it was built to
satisfy. Write a comprehensive ExUnit test harness that verifies a correct
implementation of this module.

Requirements for the harness:
- Define a module `<Module>Test` that does `use ExUnit.Case, async: false`.
- Do NOT call `ExUnit.start()` — the evaluator starts ExUnit itself.
- Make it self-contained: any fakes, clock Agents, or helpers are defined inline.
- Cover the full public API and the important edge cases described in the spec.
- It must compile with ZERO warnings (prefix unused variables with `_`; match float
  zero as `+0.0`/`-0.0`).
- Give me the complete harness in a single file.

## Original specification

Write me a set of Elixir modules that implement a **multi-channel fan-in long-polling notifications endpoint**. Instead of one stream per user, each client subscribes to several named channels at once and the long-poll returns the first notification that arrives on **any** of them, tagged with which channel it came from. I need three pieces:

## 1. `Notifications` module

This module manages per-`(user_id, channel)` pub/sub. It should provide:

- `Notifications.start_link(opts)` — starts whatever backing process is needed. Accept a `:name` option for registration (default `Notifications`). The module must also be startable under a supervisor via the `{Notifications, name: ...}` child-spec form (i.e. provide a `child_spec/1`), since the tests bring it up with `start_supervised!({Notifications, name: server})`.

- `Notifications.subscribe(server \\ Notifications, user_id, channel)` — subscribes the calling process to a single `(user_id, channel)` pair. When a notification is published to that pair, the subscribing process should receive a message `{:notification, channel, payload}`. Returns `:ok`.

- `Notifications.publish(server \\ Notifications, user_id, channel, payload)` — publishes `payload` to all processes subscribed to `(user_id, channel)`. Returns `:ok` (including when there are no subscribers).

Use only OTP primitives (e.g., `Registry`, `GenServer`, `Process`). Do not pull in Phoenix.PubSub or any external dependencies. A `Registry` in `:duplicate` mode keyed on `{user_id, channel}` is a fine backing store.

## 2. `NotificationPoller` Plug

Build a Plug module `NotificationPoller` that implements `GET /api/notifications/poll`. It must:

- Accept a `:notifications_server` option and a `:timeout_ms` option (max time to hold the connection open, default `30_000`).

- Extract the user ID from the connection assigns at `conn.assigns.user_id`. If `user_id` is missing, return 401 with body `"unauthorized"`.

- Read the requested channels from the `channels` query parameter — a comma-separated list (e.g. `?channels=orders,alerts,dm`). If the parameter is absent or resolves to an empty list, return 400 with body `"no channels"`.

- Subscribe to `(user_id, channel)` for **each** requested channel, then block (using a single `receive` with `after`) waiting for the first `{:notification, channel, payload}` message from any of them.

- If a notification arrives within the timeout, return 200 with `content-type: application/json` and a JSON body of the shape `{"channel": channel, "payload": payload}` identifying which channel fired.

- If the timeout expires with no notification, return 204 No Content with an empty body.

Use `Jason` for JSON encoding (the only external dependency allowed).

## 3. `NotificationRouter` Plug.Router

Build a thin `NotificationRouter` using `Plug.Router` that:

- Has a `plug :match` and `plug :dispatch` pipeline.
- Forwards `GET /api/notifications/poll` to `NotificationPoller`.
- Returns 404 for anything else.
- Accepts the same `:notifications_server` and `:timeout_ms` options and passes them through to the poller.

## General requirements

- All modules go in a single file.
- No external dependencies except `Jason` and `Plug`.
- The long-poll must truly hold the connection open (a single blocking `receive` across all channels), not a polling loop with `Process.sleep`.
- Only the first notification (on whichever channel) is returned; the rest can stay in the mailbox.
- Keep the implementation straightforward — no GenStage, no Phoenix Channels, no websockets.

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
