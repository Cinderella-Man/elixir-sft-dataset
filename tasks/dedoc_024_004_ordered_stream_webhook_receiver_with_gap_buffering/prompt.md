# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule WebhookReceiver.Signature do
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
  @callback deliver(store :: pid() | atom(), event :: map()) ::
              {:ok, :received | :duplicate | :buffered}
  @callback last_sequence(store :: pid() | atom(), stream_id :: String.t()) :: non_neg_integer()
  @callback delivered_events(store :: pid() | atom(), stream_id :: String.t()) :: [map()]
  @callback buffered_sequences(store :: pid() | atom(), stream_id :: String.t()) :: [integer()]

  def deliver(store, event), do: GenServer.call(store, {:deliver, event})

  def last_sequence(store, stream_id), do: GenServer.call(store, {:last_sequence, stream_id})

  def delivered_events(store, stream_id) do
    GenServer.call(store, {:delivered_events, stream_id})
  end

  def buffered_sequences(store, stream_id),
    do: GenServer.call(store, {:buffered_sequences, stream_id})
end

defmodule WebhookReceiver.MemoryStore do
  @behaviour WebhookReceiver.Store
  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @impl WebhookReceiver.Store
  def deliver(store, event), do: GenServer.call(store, {:deliver, event})

  @impl WebhookReceiver.Store
  def last_sequence(store, stream_id), do: GenServer.call(store, {:last_sequence, stream_id})

  @impl WebhookReceiver.Store
  def delivered_events(store, stream_id),
    do: GenServer.call(store, {:delivered_events, stream_id})

  @impl WebhookReceiver.Store
  def buffered_sequences(store, stream_id),
    do: GenServer.call(store, {:buffered_sequences, stream_id})

  @impl GenServer
  def init(_opts), do: {:ok, %{streams: %{}}}

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
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
```
