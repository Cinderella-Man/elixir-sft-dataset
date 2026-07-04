# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

  plug :match
  plug :dispatch

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
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule WebhookReceiverOrderedTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  @secret "whsec_ordered_secret"

  defp sign(payload, secret) do
    :crypto.mac(:hmac, :sha256, secret, payload) |> Base.encode16(case: :lower)
  end

  defp build_event(id, sid, seq, type \\ "charge.completed") do
    Jason.encode!(%{"id" => id, "stream_id" => sid, "sequence" => seq, "type" => type})
  end

  defp json_body(conn), do: Jason.decode!(conn.resp_body)

  setup do
    {:ok, store} = WebhookReceiver.MemoryStore.start_link([])
    %{store: store, opts: [secret: @secret, store: store]}
  end

  defp do_request(opts, method, path, payload, headers \\ []) do
    conn = conn(method, path, payload)

    conn =
      Enum.reduce(headers, conn, fn {k, v}, acc -> put_req_header(acc, k, v) end)

    conn = put_req_header(conn, "content-type", "application/json")
    WebhookReceiver.Router.call(conn, WebhookReceiver.Router.init(opts))
  end

  defp post_signed(opts, payload) do
    do_request(opts, :post, "/api/webhooks/stripe", payload, [
      {"stripe-signature", sign(payload, @secret)}
    ])
  end

  defp deliver(opts, id, sid, seq) do
    post_signed(opts, build_event(id, sid, seq))
  end

  test "in-order deliveries are all received", %{opts: opts, store: store} do
    for seq <- 1..3 do
      conn = deliver(opts, "e#{seq}", "s1", seq)
      assert conn.status == 200
      assert json_body(conn)["status"] == "received"
    end

    assert WebhookReceiver.Store.last_sequence(store, "s1") == 3
    seqs = WebhookReceiver.Store.delivered_events(store, "s1") |> Enum.map(& &1.sequence)
    assert seqs == [1, 2, 3]
    assert WebhookReceiver.Store.buffered_sequences(store, "s1") == []
  end

  test "delivered events are marked :delivered", %{opts: opts, store: store} do
    assert deliver(opts, "e1", "s1", 1).status == 200
    [event] = WebhookReceiver.Store.delivered_events(store, "s1")
    assert event.status == :delivered
    assert event.event_id == "e1"
  end

  test "future event is buffered with 202 then drained when gap fills", %{opts: opts, store: store} do
    assert json_body(deliver(opts, "e1", "s1", 1))["status"] == "received"

    conn3 = deliver(opts, "e3", "s1", 3)
    assert conn3.status == 202
    assert json_body(conn3)["status"] == "buffered"
    assert WebhookReceiver.Store.last_sequence(store, "s1") == 1
    assert WebhookReceiver.Store.buffered_sequences(store, "s1") == [3]

    conn2 = deliver(opts, "e2", "s1", 2)
    assert conn2.status == 200
    assert json_body(conn2)["status"] == "received"

    assert WebhookReceiver.Store.last_sequence(store, "s1") == 3
    assert WebhookReceiver.Store.buffered_sequences(store, "s1") == []
    seqs = WebhookReceiver.Store.delivered_events(store, "s1") |> Enum.map(& &1.sequence)
    assert seqs == [1, 2, 3]
  end

  test "long gap drains multiple buffered events in order", %{opts: opts, store: store} do
    # TODO
  end

  test "already-delivered sequence returns duplicate", %{opts: opts, store: store} do
    assert deliver(opts, "e1", "s1", 1).status == 200
    conn = deliver(opts, "e1", "s1", 1)
    assert conn.status == 200
    assert json_body(conn)["status"] == "duplicate"
    assert WebhookReceiver.Store.last_sequence(store, "s1") == 1
  end

  test "re-sending an already-buffered sequence returns duplicate", %{opts: opts, store: store} do
    assert deliver(opts, "e1", "s1", 1).status == 200
    assert deliver(opts, "e3", "s1", 3).status == 202

    conn = deliver(opts, "e3", "s1", 3)
    assert conn.status == 200
    assert json_body(conn)["status"] == "duplicate"
    assert WebhookReceiver.Store.buffered_sequences(store, "s1") == [3]
  end

  test "streams are independent", %{opts: opts, store: store} do
    assert deliver(opts, "a1", "sa", 1).status == 200
    assert deliver(opts, "b3", "sb", 3).status == 202

    assert WebhookReceiver.Store.last_sequence(store, "sa") == 1
    assert WebhookReceiver.Store.last_sequence(store, "sb") == 0
    assert WebhookReceiver.Store.buffered_sequences(store, "sb") == [3]
  end

  test "invalid signature returns 401", %{opts: opts} do
    payload = build_event("e1", "s1", 1)

    conn =
      do_request(opts, :post, "/api/webhooks/stripe", payload, [
        {"stripe-signature", sign(payload, "wrong")}
      ])

    assert conn.status == 401
    assert json_body(conn)["error"] == "invalid_signature"
  end

  test "missing stream_id returns bad_payload", %{opts: opts} do
    payload = Jason.encode!(%{"id" => "e1", "sequence" => 1})
    conn = post_signed(opts, payload)
    assert conn.status == 400
    assert json_body(conn)["error"] == "bad_payload"
  end

  test "missing sequence returns bad_payload", %{opts: opts} do
    payload = Jason.encode!(%{"id" => "e1", "stream_id" => "s1"})
    conn = post_signed(opts, payload)
    assert conn.status == 400
    assert json_body(conn)["error"] == "bad_payload"
  end

  test "non-integer sequence returns bad_payload", %{opts: opts} do
    payload = Jason.encode!(%{"id" => "e1", "stream_id" => "s1", "sequence" => "3"})
    conn = post_signed(opts, payload)
    assert conn.status == 400
    assert json_body(conn)["error"] == "bad_payload"
  end

  test "malformed JSON returns bad_payload", %{opts: opts} do
    conn = post_signed(opts, "not json {{")
    assert conn.status == 400
    assert json_body(conn)["error"] == "bad_payload"
  end

  test "Store.deliver/2 directly buffers and drains", %{store: store} do
    e1 = %{event_id: "e1", stream_id: "z", sequence: 1, payload: %{}, status: :pending}
    e2 = %{event_id: "e2", stream_id: "z", sequence: 2, payload: %{}, status: :pending}

    assert {:ok, :buffered} = WebhookReceiver.Store.deliver(store, e2)
    assert {:ok, :received} = WebhookReceiver.Store.deliver(store, e1)
    assert WebhookReceiver.Store.last_sequence(store, "z") == 2
  end

  test "Signature.verify/3 basics" do
    assert :ok = WebhookReceiver.Signature.verify("p", sign("p", @secret), @secret)
    assert :error = WebhookReceiver.Signature.verify("p", "deadbeef", @secret)
    assert :error = WebhookReceiver.Signature.verify(nil, "x", @secret)
  end

  test "GET to webhook path returns 404 or 405", %{opts: opts} do
    conn = do_request(opts, :get, "/api/webhooks/stripe", "")
    assert conn.status in [404, 405]
  end
end
```
