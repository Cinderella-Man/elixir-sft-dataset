defmodule WebhookReceiver do
  @moduledoc """
  A small, dependency-light webhook receiver.

  It exposes a `Plug`-based HTTP endpoint that authenticates incoming webhook
  payloads with an HMAC-SHA256 signature and then delivers them to a store in
  strict, per-stream sequence order.

  Every webhook belongs to a logical stream (`"stream_id"`) and carries a
  monotonically increasing `"sequence"` number. Events are applied to a stream
  only when their sequence directly follows the last delivered one. An event
  that arrives too early (a "future" event) is buffered until the gap in front
  of it is filled, at which point the buffer is drained in ascending, gapless
  order.

  The pieces are:

    * `WebhookReceiver.Signature` — HMAC-SHA256 signature computation/verification.
    * `WebhookReceiver.Store` — the store behaviour plus client API.
    * `WebhookReceiver.MemoryStore` — an in-memory `GenServer` store.
    * `WebhookReceiver.Router` — the `Plug.Router` HTTP endpoint.

  ## Example

      {:ok, store} = WebhookReceiver.MemoryStore.start_link([])
      opts = WebhookReceiver.Router.init(secret: "s3cret", store: store)
      Plug.Cowboy.http(WebhookReceiver.Router, opts)

  """
end

defmodule WebhookReceiver.Signature do
  @moduledoc """
  HMAC-SHA256 signature helpers for raw webhook payloads.

  A signature is the lowercase, hex-encoded HMAC-SHA256 of the *raw* request
  body, keyed with the shared secret. Verification uses a constant-time
  comparison so that a signature cannot be recovered byte-by-byte through
  timing observations.
  """

  @doc """
  Computes the lowercase hex-encoded HMAC-SHA256 of `payload` using `secret`.

  ## Examples

      iex> WebhookReceiver.Signature.sign("hello", "secret") |> byte_size()
      64

  """
  @spec sign(binary(), binary()) :: String.t()
  def sign(payload, secret) when is_binary(payload) and is_binary(secret) do
    :hmac
    |> :crypto.mac(:sha256, secret, payload)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Verifies `signature` against the HMAC-SHA256 of `payload` keyed with `secret`.

  Returns `:ok` when the provided signature matches the expected lowercase hex
  digest, `:error` otherwise. Any non-binary argument yields `:error`.

  ## Examples

      iex> sig = WebhookReceiver.Signature.sign("body", "secret")
      iex> WebhookReceiver.Signature.verify("body", sig, "secret")
      :ok

      iex> WebhookReceiver.Signature.verify("body", "deadbeef", "secret")
      :error

      iex> WebhookReceiver.Signature.verify("body", nil, "secret")
      :error

  """
  @spec verify(term(), term(), term()) :: :ok | :error
  def verify(payload, signature, secret)
      when is_binary(payload) and is_binary(signature) and is_binary(secret) do
    if secure_equal?(sign(payload, secret), signature), do: :ok, else: :error
  end

  def verify(_payload, _signature, _secret), do: :error

  @spec secure_equal?(binary(), binary()) :: boolean()
  defp secure_equal?(left, right) when byte_size(left) == byte_size(right) do
    :crypto.hash_equals(left, right)
  end

  defp secure_equal?(_left, _right), do: false
end

defmodule WebhookReceiver.Store do
  @moduledoc """
  Behaviour (and client API) for ordered, per-stream webhook delivery.

  A store keeps, for each `stream_id`, the sequence number of the last
  *delivered* event (starting at `0`) plus a buffer of future events that
  cannot be applied yet because of a gap.

  Implementations must obey these rules for `c:deliver/2`:

    * `sequence == last_seq + 1` → deliver the event, then drain any
      consecutive buffered events, and reply `{:ok, :received}`.
    * `sequence <= last_seq`, or the exact sequence is already buffered →
      `{:ok, :duplicate}`.
    * `sequence > last_seq + 1` → buffer the event and reply `{:ok, :buffered}`.

  The functions defined in this module are thin clients that dispatch to a
  store process, so callers can use `WebhookReceiver.Store.deliver(store, event)`
  regardless of the concrete implementation.
  """

  @typedoc "A store process: a pid, a registered name, or any `t:GenServer.server/0`."
  @type store :: GenServer.server()

  @typedoc "The identifier of a logical webhook stream."
  @type stream_id :: String.t()

  @typedoc "A webhook event handled by a store."
  @type event :: %{
          required(:event_id) => String.t(),
          required(:stream_id) => stream_id(),
          required(:sequence) => integer(),
          required(:payload) => map(),
          required(:status) => :pending | :delivered,
          optional(atom()) => term()
        }

  @typedoc "The outcome of a delivery attempt."
  @type outcome :: :received | :duplicate | :buffered

  @typedoc "The reply returned by `c:deliver/2`."
  @type result :: {:ok, outcome()}

  @doc """
  Delivers `event` to `store`, respecting per-stream ordering.
  """
  @callback deliver(store(), event()) :: result()

  @doc """
  Returns the last delivered sequence for `stream_id` (`0` when nothing was delivered).
  """
  @callback last_sequence(store(), stream_id()) :: non_neg_integer()

  @doc """
  Returns the events delivered on `stream_id`, in delivery order.
  """
  @callback delivered_events(store(), stream_id()) :: [event()]

  @doc """
  Returns the sorted sequence numbers currently buffered for `stream_id`.
  """
  @callback buffered_sequences(store(), stream_id()) :: [integer()]

  @doc """
  Delivers `event` to `store`.

  Returns `{:ok, :received}`, `{:ok, :duplicate}` or `{:ok, :buffered}` following
  the ordering rules described in the module documentation.
  """
  @spec deliver(store(), event()) :: result()
  def deliver(store, event) when is_map(event) do
    GenServer.call(store, {:deliver, event})
  end

  @doc """
  Returns the last delivered sequence number for `stream_id`, or `0`.
  """
  @spec last_sequence(store(), stream_id()) :: non_neg_integer()
  def last_sequence(store, stream_id) do
    GenServer.call(store, {:last_sequence, stream_id})
  end

  @doc """
  Returns the events delivered on `stream_id`, oldest first.
  """
  @spec delivered_events(store(), stream_id()) :: [event()]
  def delivered_events(store, stream_id) do
    GenServer.call(store, {:delivered_events, stream_id})
  end

  @doc """
  Returns the sorted list of sequence numbers currently buffered for `stream_id`.
  """
  @spec buffered_sequences(store(), stream_id()) :: [integer()]
  def buffered_sequences(store, stream_id) do
    GenServer.call(store, {:buffered_sequences, stream_id})
  end
end

defmodule WebhookReceiver.MemoryStore do
  @moduledoc """
  An in-memory `WebhookReceiver.Store` implementation backed by a `GenServer`.

  State is a map of `stream_id => stream_state`, where each stream state holds:

    * `:last` — the last delivered sequence number (defaults to `0`);
    * `:delivered` — delivered events, newest first (reversed on read);
    * `:buffered` — a `sequence => event` map of future events awaiting a gap fill.

  Delivered events are stored with `status: :delivered`; buffered events keep
  `status: :pending` until they are drained.
  """

  use GenServer

  @behaviour WebhookReceiver.Store

  alias WebhookReceiver.Store

  @typedoc "Per-stream bookkeeping."
  @type stream_state :: %{
          last: non_neg_integer(),
          delivered: [Store.event()],
          buffered: %{optional(integer()) => Store.event()}
        }

  @typedoc "The full store state."
  @type state :: %{optional(Store.stream_id()) => stream_state()}

  @doc """
  Starts the in-memory store.

  Accepts the usual `GenServer` options (`:name`, `:timeout`, `:debug`,
  `:spawn_opt`, `:hibernate_after`); everything else is ignored.

  ## Examples

      {:ok, store} = WebhookReceiver.MemoryStore.start_link(name: :webhooks)

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {gen_opts, _rest} =
      Keyword.split(opts, [:name, :timeout, :debug, :spawn_opt, :hibernate_after])

    GenServer.start_link(__MODULE__, :ok, gen_opts)
  end

  @doc """
  Delivers `event`, applying it immediately or buffering it until the gap fills.
  """
  @impl WebhookReceiver.Store
  @spec deliver(Store.store(), Store.event()) :: Store.result()
  def deliver(store, event) when is_map(event) do
    GenServer.call(store, {:deliver, event})
  end

  @doc """
  Returns the last delivered sequence number for `stream_id` (`0` by default).
  """
  @impl WebhookReceiver.Store
  @spec last_sequence(Store.store(), Store.stream_id()) :: non_neg_integer()
  def last_sequence(store, stream_id) do
    GenServer.call(store, {:last_sequence, stream_id})
  end

  @doc """
  Returns the events delivered on `stream_id`, in delivery order.
  """
  @impl WebhookReceiver.Store
  @spec delivered_events(Store.store(), Store.stream_id()) :: [Store.event()]
  def delivered_events(store, stream_id) do
    GenServer.call(store, {:delivered_events, stream_id})
  end

  @doc """
  Returns the sorted sequence numbers currently buffered for `stream_id`.
  """
  @impl WebhookReceiver.Store
  @spec buffered_sequences(Store.store(), Store.stream_id()) :: [integer()]
  def buffered_sequences(store, stream_id) do
    GenServer.call(store, {:buffered_sequences, stream_id})
  end

  @doc false
  @impl GenServer
  @spec init(:ok) :: {:ok, state()}
  def init(:ok), do: {:ok, %{}}

  @doc false
  @impl GenServer
  @spec handle_call(term(), GenServer.from(), state()) :: {:reply, term(), state()}
  def handle_call({:deliver, event}, _from, state) do
    {reply, state} = do_deliver(state, event)
    {:reply, reply, state}
  end

  def handle_call({:last_sequence, stream_id}, _from, state) do
    {:reply, state |> stream_state(stream_id) |> Map.fetch!(:last), state}
  end

  def handle_call({:delivered_events, stream_id}, _from, state) do
    delivered = state |> stream_state(stream_id) |> Map.fetch!(:delivered) |> Enum.reverse()
    {:reply, delivered, state}
  end

  def handle_call({:buffered_sequences, stream_id}, _from, state) do
    sequences =
      state
      |> stream_state(stream_id)
      |> Map.fetch!(:buffered)
      |> Map.keys()
      |> Enum.sort()

    {:reply, sequences, state}
  end

  @spec do_deliver(state(), Store.event()) :: {Store.result(), state()}
  defp do_deliver(state, %{stream_id: stream_id, sequence: sequence} = event) do
    stream = stream_state(state, stream_id)

    cond do
      sequence <= stream.last ->
        {{:ok, :duplicate}, state}

      sequence == stream.last + 1 ->
        stream = stream |> apply_event(event) |> drain()
        {{:ok, :received}, Map.put(state, stream_id, stream)}

      Map.has_key?(stream.buffered, sequence) ->
        {{:ok, :duplicate}, state}

      true ->
        buffered = Map.put(stream.buffered, sequence, Map.put(event, :status, :pending))
        {{:ok, :buffered}, Map.put(state, stream_id, %{stream | buffered: buffered})}
    end
  end

  @spec apply_event(stream_state(), Store.event()) :: stream_state()
  defp apply_event(stream, event) do
    delivered = Map.put(event, :status, :delivered)

    %{stream | last: event.sequence, delivered: [delivered | stream.delivered]}
  end

  @spec drain(stream_state()) :: stream_state()
  defp drain(stream) do
    case Map.pop(stream.buffered, stream.last + 1) do
      {nil, _buffered} ->
        stream

      {event, buffered} ->
        %{stream | buffered: buffered}
        |> apply_event(event)
        |> drain()
    end
  end

  @spec stream_state(state(), Store.stream_id()) :: stream_state()
  defp stream_state(state, stream_id) do
    Map.get(state, stream_id, %{last: 0, delivered: [], buffered: %{}})
  end
end

defmodule WebhookReceiver.Router do
  @moduledoc """
  A `Plug.Router` exposing `POST /api/webhooks/stripe`.

  ## Options

    * `:secret` — the shared secret used to verify the `stripe-signature` header;
    * `:store` — the `WebhookReceiver.Store` process events are delivered to.

  ## Behaviour

  The raw body is read once (signature verification must happen over the exact
  bytes that were signed). A missing, empty or invalid signature results in
  `401 {"error": "invalid_signature"}`.

  The body must be a JSON object with a string `"id"`, a string `"stream_id"`
  and an integer `"sequence"`. Malformed JSON or a missing/wrongly typed field
  results in `400 {"error": "bad_payload"}`.

  Otherwise the event is delivered to the store and the reply is:

    * `200 {"status": "received"}` when the event was applied;
    * `200 {"status": "duplicate"}` when it had already been seen;
    * `202 {"status": "buffered"}` when it arrived ahead of a gap.

  """

  use Plug.Router

  alias WebhookReceiver.Signature
  alias WebhookReceiver.Store

  @signature_header "stripe-signature"
  @max_body_bytes 8_000_000

  plug :match
  plug :dispatch

  @doc """
  Initializes the router options.

  Accepts a keyword list or map carrying `:secret` and `:store`.
  """
  @spec init(keyword() | map()) :: keyword() | map()
  def init(opts), do: opts

  @doc """
  Entry point of the plug pipeline.

  Stashes the normalized router options in `conn.private` so the matched route
  can reach the configured secret and store, then delegates to `Plug.Router`.
  """
  @spec call(Plug.Conn.t(), keyword() | map()) :: Plug.Conn.t()
  def call(conn, opts) do
    conn
    |> put_private(:webhook_receiver, normalize_opts(opts))
    |> super(opts)
  end

  post "/api/webhooks/stripe" do
    %{secret: secret, store: store} = conn.private.webhook_receiver

    case read_raw_body(conn) do
      {:ok, body, conn} -> authenticate(conn, body, secret, store)
      {:error, conn} -> send_json(conn, 400, %{"error" => "bad_payload"})
    end
  end

  match _ do
    send_json(conn, 404, %{"error" => "not_found"})
  end

  @spec normalize_opts(keyword() | map()) :: %{secret: binary(), store: Store.store()}
  defp normalize_opts(opts) when is_list(opts), do: normalize_opts(Map.new(opts))

  defp normalize_opts(opts) when is_map(opts) do
    %{secret: Map.fetch!(opts, :secret), store: Map.fetch!(opts, :store)}
  end

  @spec read_raw_body(Plug.Conn.t(), iodata()) ::
          {:ok, binary(), Plug.Conn.t()} | {:error, Plug.Conn.t()}
  defp read_raw_body(conn, acc \\ []) do
    case Plug.Conn.read_body(conn, length: @max_body_bytes) do
      {:ok, chunk, conn} -> {:ok, IO.iodata_to_binary([acc, chunk]), conn}
      {:more, chunk, conn} -> read_raw_body(conn, [acc, chunk])
      {:error, _reason} -> {:error, conn}
    end
  end

  @spec authenticate(Plug.Conn.t(), binary(), binary(), Store.store()) :: Plug.Conn.t()
  defp authenticate(conn, body, secret, store) do
    with [signature | _rest] <- get_req_header(conn, @signature_header),
         true <- is_binary(signature) and signature != "",
         :ok <- Signature.verify(body, signature, secret) do
      process(conn, body, store)
    else
      _other -> send_json(conn, 401, %{"error" => "invalid_signature"})
    end
  end

  @spec process(Plug.Conn.t(), binary(), Store.store()) :: Plug.Conn.t()
  defp process(conn, body, store) do
    case decode_event(body) do
      {:ok, event} -> respond(conn, Store.deliver(store, event))
      :error -> send_json(conn, 400, %{"error" => "bad_payload"})
    end
  end

  @spec respond(Plug.Conn.t(), Store.result()) :: Plug.Conn.t()
  defp respond(conn, {:ok, :received}), do: send_json(conn, 200, %{"status" => "received"})
  defp respond(conn, {:ok, :duplicate}), do: send_json(conn, 200, %{"status" => "duplicate"})
  defp respond(conn, {:ok, :buffered}), do: send_json(conn, 202, %{"status" => "buffered"})

  @spec decode_event(binary()) :: {:ok, Store.event()} | :error
  defp decode_event(body) do
    case Jason.decode(body) do
      {:ok, %{"id" => id, "stream_id" => stream_id, "sequence" => sequence} = payload}
      when is_binary(id) and is_binary(stream_id) and is_integer(sequence) ->
        {:ok,
         %{
           event_id: id,
           stream_id: stream_id,
           sequence: sequence,
           payload: payload,
           status: :pending
         }}

      _other ->
        :error
    end
  end

  @spec send_json(Plug.Conn.t(), 200..599, map()) :: Plug.Conn.t()
  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end