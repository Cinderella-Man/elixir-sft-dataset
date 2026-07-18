# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `publish` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me a set of Elixir modules that implement a **coalescing (batching) long-polling notifications endpoint**. Unlike a plain long-poll that returns the single first notification, this one waits for the first notification and then keeps the connection open for a short "linger" window to gather any additional notifications that arrive in that burst, returning them all in one batched response. I need three pieces:

## 1. `Notifications` module

This module manages pub/sub for user notifications. It should provide:

- `Notifications.start_link(opts)` — starts whatever backing process is needed. Accept a `:name` option for registration (default `Notifications`). The module must also be startable under a supervisor as `{Notifications, opts}` (e.g. via `start_supervised!({Notifications, name: server})` and `start_supervised!({Notifications, []})`), so provide a `child_spec/1` if your backing process does not already supply one.

- `Notifications.subscribe(server \\ Notifications, user_id)` — subscribes the calling process to notifications for the given `user_id`. When a notification is published for that user, the subscribing process should receive a message `{:notification, payload}`.

- `Notifications.publish(server \\ Notifications, user_id, payload)` — publishes `payload` to all processes currently subscribed to `user_id`. Returns `:ok`, including when there are no subscribers.

Use only OTP primitives (e.g., `Registry`, `GenServer`, `Process`). Do not pull in Phoenix.PubSub or any external dependencies. A `Registry` in `:duplicate` mode is a fine backing store, and it lets multiple processes subscribe to the same `user_id` and each receive the full burst.

## 2. `NotificationPoller` Plug

Build a Plug module `NotificationPoller` that implements `GET /api/notifications/poll`. It must:

- Accept a `:notifications_server` option, a `:timeout_ms` option (max time to wait for the FIRST notification, default `30_000`), and a `:linger_ms` option (how long to keep draining additional notifications after the first arrives, default `50`).

- Extract the user ID from the connection assigns at `conn.assigns.user_id`. If `user_id` is missing, return 401 with body exactly `"unauthorized"`.

- Subscribe to `Notifications` for that user, then block (using a `receive` with `after`) waiting for the first `{:notification, payload}` message.

- Once the first notification arrives, open a linger window: keep draining `{:notification, payload}` messages with a `receive` whose `after` is `:linger_ms`, accumulating payloads until a full `:linger_ms` elapses with no further message. Each new message resets the window, so a burst whose gaps are each shorter than `:linger_ms` is collected in full even if its total span runs past the original `:timeout_ms`. Preserve arrival order.

- Return 200 with `content-type: application/json` and a JSON body of the shape `{"notifications": [payload, ...], "count": n}`, where the array contains **every** payload collected during the burst in arrival order and `count` is the number of payloads.

- If the `:timeout_ms` expires before any notification arrives, return 204 No Content with an empty body (`""`).

Use `Jason` for JSON encoding (the only external dependency allowed).

## 3. `NotificationRouter` Plug.Router

Build a thin `NotificationRouter` using `Plug.Router` that:

- Has a `plug :match` and `plug :dispatch` pipeline.
- Forwards `GET /api/notifications/poll` to `NotificationPoller`.
- Returns 404 for anything else.
- Accepts the same `:notifications_server`, `:timeout_ms`, and `:linger_ms` options and passes them through to the poller.

## General requirements

- All modules go in a single file.
- No external dependencies except `Jason` and `Plug`.
- The long-poll must truly hold the connection open (a blocking `receive`), not a polling loop with `Process.sleep`.
- A single notification must still be returned as a one-element batch; the linger window is about coalescing bursts, not a maximum batch size.
- Keep the implementation straightforward — no GenStage, no Phoenix Channels, no websockets.

## The module with `publish` missing

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

  def publish(server \\ __MODULE__, user_id, payload) do
    # TODO
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

Give me only the complete implementation of `publish` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
