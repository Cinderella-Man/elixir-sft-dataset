# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `send_json` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

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

## The module with `send_json` missing

```elixir
defmodule WebhookReceiver.Signature do
  @moduledoc """
  HMAC-SHA256 signature verification for webhook payloads.
  """

  @doc """
  Verifies `signature` against the lowercase hex HMAC-SHA256 of `payload`
  computed with `secret`, using a constant-time comparison.

  Returns `:ok` on match and `:error` otherwise, including when any argument is
  not a binary.
  """
  @spec verify(term(), term(), term()) :: :ok | :error
  def verify(payload, signature, secret)
      when is_binary(payload) and is_binary(signature) and is_binary(secret) do
    expected = :crypto.mac(:hmac, :sha256, secret, payload) |> Base.encode16(case: :lower)

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
  Behaviour describing an ordered, per-stream webhook delivery store.
  """

  @callback deliver(store :: pid() | atom(), event :: map()) ::
              {:ok, :received | :duplicate | :buffered}
  @callback last_sequence(store :: pid() | atom(), stream_id :: String.t()) :: non_neg_integer()
  @callback delivered_events(store :: pid() | atom(), stream_id :: String.t()) :: [map()]
  @callback buffered_sequences(store :: pid() | atom(), stream_id :: String.t()) :: [integer()]

  @doc """
  Delivers `event` to `store`, returning the delivery outcome tuple.
  """
  @spec deliver(pid() | atom(), map()) :: {:ok, :received | :duplicate | :buffered}
  def deliver(store, event), do: GenServer.call(store, {:deliver, event})

  @doc """
  Returns the last delivered sequence for `stream_id` (default `0`).
  """
  @spec last_sequence(pid() | atom(), String.t()) :: non_neg_integer()
  def last_sequence(store, stream_id), do: GenServer.call(store, {:last_sequence, stream_id})

  @doc """
  Returns the delivered events for `stream_id` in delivery order.
  """
  @spec delivered_events(pid() | atom(), String.t()) :: [map()]
  def delivered_events(store, stream_id) do
    GenServer.call(store, {:delivered_events, stream_id})
  end

  @doc """
  Returns the sorted list of currently-buffered sequence numbers for `stream_id`.
  """
  @spec buffered_sequences(pid() | atom(), String.t()) :: [integer()]
  def buffered_sequences(store, stream_id),
    do: GenServer.call(store, {:buffered_sequences, stream_id})
end

defmodule WebhookReceiver.MemoryStore do
  @moduledoc """
  In-memory `GenServer` implementation of `WebhookReceiver.Store` with per-stream
  ordering and gap buffering.
  """

  @behaviour WebhookReceiver.Store
  use GenServer

  @doc """
  Starts the store. Accepts standard `GenServer` options such as `:name`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @doc """
  Delivers `event` to `store`, returning the delivery outcome tuple.
  """
  @spec deliver(pid() | atom(), map()) :: {:ok, :received | :duplicate | :buffered}
  @impl WebhookReceiver.Store
  def deliver(store, event), do: GenServer.call(store, {:deliver, event})

  @doc """
  Returns the last delivered sequence for `stream_id` (default `0`).
  """
  @spec last_sequence(pid() | atom(), String.t()) :: non_neg_integer()
  @impl WebhookReceiver.Store
  def last_sequence(store, stream_id), do: GenServer.call(store, {:last_sequence, stream_id})

  @doc """
  Returns the delivered events for `stream_id` in delivery order.
  """
  @spec delivered_events(pid() | atom(), String.t()) :: [map()]
  @impl WebhookReceiver.Store
  def delivered_events(store, stream_id),
    do: GenServer.call(store, {:delivered_events, stream_id})

  @doc """
  Returns the sorted list of currently-buffered sequence numbers for `stream_id`.
  """
  @spec buffered_sequences(pid() | atom(), String.t()) :: [integer()]
  @impl WebhookReceiver.Store
  def buffered_sequences(store, stream_id),
    do: GenServer.call(store, {:buffered_sequences, stream_id})

  @doc """
  Initializes the store state with an empty stream registry.
  """
  @spec init(keyword()) :: {:ok, map()}
  @impl GenServer
  def init(_opts), do: {:ok, %{streams: %{}}}

  @doc """
  Handles synchronous store operations: delivery and per-stream inspection.
  """
  @spec handle_call(term(), GenServer.from(), map()) :: {:reply, term(), map()}
  @impl GenServer
  def handle_call({:deliver, event}, _from, %{streams: streams} = state) do
    sid = event.stream_id
    seq = event.sequence
    stream = Map.get(streams, sid, %{last_seq: 0, buffer: %{}, delivered: []})
    %{last_seq: last_seq, buffer: buffer, delivered: delivered} = stream

    cond do
      seq <= last_seq ->
        {:reply, {:ok, :duplicate}, state}

      Map.has_key?(buffer, seq) ->
        {:reply, {:ok, :duplicate}, state}

      seq == last_seq + 1 ->
        {new_last, new_buffer, new_delivered} =
          drain(last_seq, buffer, delivered, %{event | status: :delivered})

        new_stream = %{last_seq: new_last, buffer: new_buffer, delivered: new_delivered}
        {:reply, {:ok, :received}, %{state | streams: Map.put(streams, sid, new_stream)}}

      true ->
        new_stream = %{stream | buffer: Map.put(buffer, seq, %{event | status: :pending})}
        {:reply, {:ok, :buffered}, %{state | streams: Map.put(streams, sid, new_stream)}}
    end
  end

  @impl GenServer
  def handle_call({:last_sequence, sid}, _from, %{streams: streams} = state) do
    {:reply, stream(streams, sid).last_seq, state}
  end

  @impl GenServer
  def handle_call({:delivered_events, sid}, _from, %{streams: streams} = state) do
    {:reply, stream(streams, sid).delivered, state}
  end

  @impl GenServer
  def handle_call({:buffered_sequences, sid}, _from, %{streams: streams} = state) do
    {:reply, streams |> stream(sid) |> Map.fetch!(:buffer) |> Map.keys() |> Enum.sort(), state}
  end

  defp stream(streams, sid), do: Map.get(streams, sid, %{last_seq: 0, buffer: %{}, delivered: []})

  # Applies `event` (whose sequence is last_seq + 1), then keeps applying
  # consecutive buffered events until the first gap.
  defp drain(last_seq, buffer, delivered, event) do
    delivered = delivered ++ [event]
    last_seq = last_seq + 1

    case Map.pop(buffer, last_seq + 1) do
      {nil, _buffer} -> {last_seq, buffer, delivered}
      {next, rest} -> drain(last_seq, rest, delivered, %{next | status: :delivered})
    end
  end
end

defmodule WebhookReceiver.Router do
  @moduledoc """
  `Plug.Router` receiving Stripe-style webhooks with per-stream ordered delivery.
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
      {:ok, %{"id" => id, "stream_id" => sid, "sequence" => seq} = payload}
      when is_binary(id) and is_binary(sid) and is_integer(seq) ->
        event = %{
          event_id: id,
          stream_id: sid,
          sequence: seq,
          payload: payload,
          status: :pending
        }

        case Store.deliver(store, event) do
          {:ok, :received} -> send_json(conn, 200, %{status: "received"})
          {:ok, :duplicate} -> send_json(conn, 200, %{status: "duplicate"})
          {:ok, :buffered} -> send_json(conn, 202, %{status: "buffered"})
        end

      {:ok, _decoded} ->
        send_json(conn, 400, %{error: "bad_payload"})

      {:error, _reason} ->
        send_json(conn, 400, %{error: "bad_payload"})
    end
  end

  defp send_json(conn, status, data) do
    # TODO
  end
end
```

Give me only the complete implementation of `send_json` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
