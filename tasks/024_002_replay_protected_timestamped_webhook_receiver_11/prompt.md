# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `sign` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir module called `WebhookReceiver` that implements a Plug-based HTTP endpoint for receiving webhook payloads using **replay-protected, timestamped HMAC-SHA256 signatures** (the Stripe `t=...,v1=...` scheme).

I need these modules:

1. `WebhookReceiver.Signature` — a module with:
   - `sign(timestamp, payload, secret)` — compute HMAC-SHA256 of the string `"<timestamp>.<payload>"` using `secret` and return it hex-encoded (lowercase).
   - `parse(header)` — parse a signature header of the form `"t=1700000000,v1=abcdef..."` into a map like `%{"t" => "1700000000", "v1" => "abcdef..."}`. Return `%{}` for anything that is not a binary.

2. `WebhookReceiver.Store` — a behaviour with callbacks:
   - `store_event(store, event_id, payload)` — persist with status `:pending`; `{:ok, :duplicate}` if the id already exists, `{:ok, :created}` if new.
   - `get_event(store, event_id)` — `{:ok, event}` or `:error`.
   - `all_events(store)` — all stored events as a list.

3. `WebhookReceiver.MemoryStore` — a GenServer implementing the behaviour with an in-memory map. Each event is a map with at least `:event_id`, `:payload` (decoded map), and `:status` (`:pending` on creation).

4. `WebhookReceiver.Router` — a `Plug.Router` exposing `POST /api/webhooks/stripe`. Options:
   - `:secret` — the HMAC signing key (required).
   - `:store` — the store process (required).
   - `:tolerance` — max allowed clock skew in seconds (default `300`).
   - `:now` — either an integer Unix-second timestamp or a 0-arity function returning one, used as "current time" (default `System.system_time(:second)`).

Router behaviour:
- Read the raw body once and the `stripe-signature` header.
- If the header is missing/empty, cannot be parsed into both a `t` and a `v1` field, has a non-integer `t`, or produces a signature that does not match, return **401** with `{"error": "invalid_signature"}`.
- If the header's timestamp is a valid integer but outside the tolerance window (`abs(now - t) > tolerance`), return **401** with `{"error": "timestamp_expired"}` (check this before rejecting on signature mismatch).
- On a valid, in-window signature, decode the JSON, extract the `"id"` field:
  - already stored → **200** `{"status": "duplicate"}`
  - new → store and **200** `{"status": "received"}`
- Malformed JSON or missing `"id"` → **400** `{"error": "bad_payload"}`.

The raw body must be available for both signature verification and JSON decoding. Use only Plug and Jason (plus `:crypto` from OTP). No Phoenix, no Ecto. Give me all modules in a single file.

## Additional interface contract

- `WebhookReceiver.Store` is not just a behaviour definition: it must ALSO define public client functions with the same names and arities as its callbacks, each dispatching to the given store process (e.g. via `GenServer.call(store, ...)`), so callers can invoke e.g. `WebhookReceiver.Store.get_event(store, event_id)` directly on the module.

## The module with `sign` missing

```elixir
defmodule WebhookReceiver.Signature do
  @moduledoc """
  Replay-protected timestamped HMAC-SHA256 signatures (Stripe `t=,v1=` scheme).
  """

  def sign(timestamp, payload, secret) when is_binary(payload) and is_binary(secret) do
    # TODO
  end

  @doc """
  Parses a header like `"t=123,v1=abc"` into a map of string keys/values.

  Returns `%{}` for any non-binary input.
  """
  @spec parse(term()) :: %{optional(String.t()) => String.t()}
  def parse(header) when is_binary(header) do
    header
    |> String.split(",", trim: true)
    |> Enum.reduce(%{}, fn part, acc ->
      case String.split(part, "=", parts: 2) do
        [k, v] -> Map.put(acc, String.trim(k), String.trim(v))
        _ -> acc
      end
    end)
  end

  def parse(_), do: %{}
end

defmodule WebhookReceiver.Store do
  @moduledoc """
  Behaviour describing a webhook event store plus client functions.
  """

  @callback store_event(store :: pid() | atom(), event_id :: String.t(), payload :: map()) ::
              {:ok, :created | :duplicate}
  @callback get_event(store :: pid() | atom(), event_id :: String.t()) ::
              {:ok, map()} | :error
  @callback all_events(store :: pid() | atom()) :: [map()]

  @doc """
  Persists `payload` under `event_id`; returns `{:ok, :created}` or `{:ok, :duplicate}`.
  """
  @spec store_event(pid() | atom(), String.t(), map()) :: {:ok, :created | :duplicate}
  def store_event(store, event_id, payload) do
    GenServer.call(store, {:store_event, event_id, payload})
  end

  @doc """
  Fetches a stored event; returns `{:ok, event}` or `:error`.
  """
  @spec get_event(pid() | atom(), String.t()) :: {:ok, map()} | :error
  def get_event(store, event_id) do
    GenServer.call(store, {:get_event, event_id})
  end

  @doc """
  Returns all stored events as a list.
  """
  @spec all_events(pid() | atom()) :: [map()]
  def all_events(store) do
    GenServer.call(store, :all_events)
  end
end

defmodule WebhookReceiver.MemoryStore do
  @moduledoc """
  In-memory `GenServer` implementation of `WebhookReceiver.Store`.
  """

  @behaviour WebhookReceiver.Store
  use GenServer

  @doc """
  Starts the in-memory store; accepts an optional `:name` in `opts`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @doc """
  Persists `payload` under `event_id`; returns `{:ok, :created}` or `{:ok, :duplicate}`.
  """
  @spec store_event(pid() | atom(), String.t(), map()) :: {:ok, :created | :duplicate}
  @impl WebhookReceiver.Store
  def store_event(store, event_id, payload) do
    GenServer.call(store, {:store_event, event_id, payload})
  end

  @doc """
  Fetches a stored event; returns `{:ok, event}` or `:error`.
  """
  @spec get_event(pid() | atom(), String.t()) :: {:ok, map()} | :error
  @impl WebhookReceiver.Store
  def get_event(store, event_id) do
    GenServer.call(store, {:get_event, event_id})
  end

  @doc """
  Returns all stored events as a list.
  """
  @spec all_events(pid() | atom()) :: [map()]
  @impl WebhookReceiver.Store
  def all_events(store) do
    GenServer.call(store, :all_events)
  end

  @doc """
  Initializes the store state with an empty event map.
  """
  @spec init(keyword()) :: {:ok, %{events: map()}}
  @impl GenServer
  def init(_opts), do: {:ok, %{events: %{}}}

  @doc """
  Handles store, fetch and list calls against the in-memory event map.
  """
  @spec handle_call(term(), GenServer.from(), %{events: map()}) ::
          {:reply, term(), %{events: map()}}
  @impl GenServer
  def handle_call({:store_event, event_id, payload}, _from, %{events: events} = state) do
    if Map.has_key?(events, event_id) do
      {:reply, {:ok, :duplicate}, state}
    else
      event = %{event_id: event_id, payload: payload, status: :pending}
      {:reply, {:ok, :created}, %{state | events: Map.put(events, event_id, event)}}
    end
  end

  @impl GenServer
  def handle_call({:get_event, event_id}, _from, %{events: events} = state) do
    case Map.fetch(events, event_id) do
      {:ok, event} -> {:reply, {:ok, event}, state}
      :error -> {:reply, :error, state}
    end
  end

  @impl GenServer
  def handle_call(:all_events, _from, %{events: events} = state) do
    {:reply, Map.values(events), state}
  end
end

defmodule WebhookReceiver.Router do
  @moduledoc """
  `Plug.Router` receiving replay-protected Stripe-style webhooks.
  """

  use Plug.Router, copy_opts_to_assign: :webhook_opts

  alias WebhookReceiver.{Signature, Store}

  plug(:match)
  plug(:dispatch)

  post "/api/webhooks/stripe" do
    opts = conn.assigns.webhook_opts
    secret = Keyword.fetch!(opts, :secret)
    store = Keyword.fetch!(opts, :store)
    tolerance = Keyword.get(opts, :tolerance, 300)
    now = current_time(opts)

    {:ok, body, conn} = read_body(conn)
    header = conn |> get_req_header("stripe-signature") |> List.first()

    case verify_signed(header, body, secret, now, tolerance) do
      :ok -> handle_verified(conn, body, store)
      {:error, :expired} -> send_json(conn, 401, %{error: "timestamp_expired"})
      {:error, _} -> send_json(conn, 401, %{error: "invalid_signature"})
    end
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

  defp verify_signed(header, body, secret, now, tolerance) do
    parsed = if is_binary(header) and header != "", do: Signature.parse(header), else: %{}

    with %{"t" => ts_str, "v1" => v1} <- parsed,
         {ts, ""} <- Integer.parse(ts_str) do
      cond do
        abs(now - ts) > tolerance ->
          {:error, :expired}

        Plug.Crypto.secure_compare(Signature.sign(ts, body, secret), v1) ->
          :ok

        true ->
          {:error, :invalid}
      end
    else
      _ -> {:error, :invalid}
    end
  end

  defp handle_verified(conn, body, store) do
    case Jason.decode(body) do
      {:ok, %{"id" => event_id} = payload} when is_binary(event_id) ->
        case Store.store_event(store, event_id, payload) do
          {:ok, :created} -> send_json(conn, 200, %{status: "received"})
          {:ok, :duplicate} -> send_json(conn, 200, %{status: "duplicate"})
        end

      {:ok, _decoded} ->
        send_json(conn, 400, %{error: "bad_payload"})

      {:error, _reason} ->
        send_json(conn, 400, %{error: "bad_payload"})
    end
  end

  defp current_time(opts) do
    case Keyword.get(opts, :now) do
      nil -> System.system_time(:second)
      fun when is_function(fun, 0) -> fun.()
      int when is_integer(int) -> int
    end
  end

  defp send_json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
```

Give me only the complete implementation of `sign` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
