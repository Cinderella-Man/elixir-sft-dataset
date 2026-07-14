# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

```elixir
defmodule WebhookReceiver.Signature do
  @moduledoc """
  HMAC-SHA256 signature verification for webhook payloads.
  """

  @doc """
  Computes HMAC-SHA256 of `payload` with `secret` and compares it, in
  constant time, against the hex-encoded `signature`. Returns `:ok` or `:error`.
  """
  @spec verify(binary(), binary(), binary()) :: :ok | :error
  def verify(payload, signature, secret)
      when is_binary(payload) and is_binary(signature) and is_binary(secret) do
    expected =
      :crypto.mac(:hmac, :sha256, secret, payload)
      |> Base.encode16(case: :lower)

    if Plug.Crypto.secure_compare(expected, signature) do
      :ok
    else
      :error
    end
  end

  def verify(_payload, _signature, _secret), do: :error
end

defmodule WebhookReceiver.Store do
  @moduledoc """
  Behaviour describing a webhook event store plus convenience client functions
  that delegate to the store process.
  """

  @callback store_event(store :: pid() | atom(), event_id :: String.t(), payload :: map()) ::
              {:ok, :created | :duplicate}
  @callback get_event(store :: pid() | atom(), event_id :: String.t()) ::
              {:ok, map()} | :error
  @callback all_events(store :: pid() | atom()) :: [map()]

  def store_event(store, event_id, payload) do
    GenServer.call(store, {:store_event, event_id, payload})
  end

  def get_event(store, event_id) do
    GenServer.call(store, {:get_event, event_id})
  end

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

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @impl WebhookReceiver.Store
  def store_event(store, event_id, payload) do
    GenServer.call(store, {:store_event, event_id, payload})
  end

  @impl WebhookReceiver.Store
  def get_event(store, event_id) do
    GenServer.call(store, {:get_event, event_id})
  end

  @impl WebhookReceiver.Store
  def all_events(store) do
    GenServer.call(store, :all_events)
  end

  @impl GenServer
  def init(_opts), do: {:ok, %{events: %{}}}

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
  `Plug.Router` receiving Stripe-style webhooks at `POST /api/webhooks/stripe`.
  It reads the raw body once, verifies the HMAC signature, then decodes and
  stores the event.
  """

  use Plug.Router, copy_opts_to_assign: :webhook_opts

  alias WebhookReceiver.{Signature, Store}

  plug(:match)
  plug(:dispatch)

  post "/api/webhooks/stripe" do
    opts = conn.assigns.webhook_opts
    secret = Keyword.fetch!(opts, :secret)
    store = Keyword.fetch!(opts, :store)

    {:ok, body, conn} = read_body(conn)
    signature = conn |> get_req_header("stripe-signature") |> List.first()

    cond do
      is_nil(signature) or signature == "" ->
        send_json(conn, 401, %{error: "invalid_signature"})

      Signature.verify(body, signature, secret) != :ok ->
        send_json(conn, 401, %{error: "invalid_signature"})

      true ->
        handle_verified(conn, body, store)
    end
  end

  match _ do
    send_resp(conn, 404, "not found")
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

  defp send_json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
```

## New specification

Write me an Elixir module called `WebhookReceiver` that implements a Plug-based HTTP endpoint for receiving webhook payloads with HMAC-SHA256 signature verification **and ordered, per-stream delivery with gap buffering**.

Each webhook belongs to a logical stream and carries a monotonically increasing sequence number. Events must be applied strictly in order per stream; an out-of-order (future) event is buffered until the gap fills, then drained.

I need these modules:

1. `WebhookReceiver.Signature` — `verify(payload, signature, secret)` computes lowercase hex HMAC-SHA256 of the raw `payload` and constant-time compares to `signature`. Returns `:ok` or `:error` (non-binary input → `:error`).

2. `WebhookReceiver.Store` — a behaviour with callbacks:
   - `deliver(store, event)` where `event` is a map with `:event_id`, `:stream_id`, `:sequence`, `:payload`, `:status`. Per stream it tracks the last delivered sequence (starting at `0`). Returns:
     - `{:ok, :received}` when `sequence == last_seq + 1` (deliver it, then drain any consecutive buffered events).
     - `{:ok, :duplicate}` when `sequence <= last_seq`, or when that exact sequence is already buffered.
     - `{:ok, :buffered}` when `sequence > last_seq + 1` (store it for later).
   - `last_sequence(store, stream_id)` — the last delivered sequence (default `0`).
   - `delivered_events(store, stream_id)` — delivered events in delivery order.
   - `buffered_sequences(store, stream_id)` — sorted list of currently-buffered sequence numbers.

3. `WebhookReceiver.MemoryStore` — a GenServer implementing the behaviour. Delivered events should have `:status` `:delivered`; buffered events `:status` `:pending`. Draining must apply buffered events in ascending, gapless order and stop at the first gap.

4. `WebhookReceiver.Router` — a `Plug.Router` exposing `POST /api/webhooks/stripe`. Options `:secret` and `:store`.
   - Read the raw body once and the `stripe-signature` header; missing/empty header or bad signature → **401** `{"error": "invalid_signature"}`.
   - Decode the JSON and require `"id"` (string), `"stream_id"` (string), and `"sequence"` (integer). Any missing/wrong-typed field or malformed JSON → **400** `{"error": "bad_payload"}`.
   - Build the event and call `deliver/2`:
     - `:received` → **200** `{"status": "received"}`
     - `:duplicate` → **200** `{"status": "duplicate"}`
     - `:buffered` → **202** `{"status": "buffered"}`

Use only Plug and Jason (plus `:crypto`). No Phoenix, no Ecto. Give me all modules in a single file.

## Additional interface contract

- `WebhookReceiver.Store` is not just a behaviour definition: it must ALSO define public client functions with the same names and arities as its callbacks, each dispatching to the given store process (e.g. via `GenServer.call(store, ...)`), so callers can invoke e.g. `WebhookReceiver.Store.last_sequence(store, stream_id)` directly on the module.
