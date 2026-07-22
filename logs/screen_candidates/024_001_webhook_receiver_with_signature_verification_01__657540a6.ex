defmodule WebhookReceiver.Signature do
  @moduledoc """
  HMAC-SHA256 signature verification for incoming webhook payloads.

  The expected signature is the lowercase hex encoding of
  `HMAC-SHA256(secret, raw_payload)`. Comparison is done in constant time so
  that verification does not leak information about the expected digest
  through timing side channels.
  """

  @doc """
  Verifies `signature` against the HMAC-SHA256 of `payload` keyed with `secret`.

  `payload` must be the *raw* request body exactly as received — re-encoding a
  decoded JSON map will generally produce a different digest. `signature` is the
  hex-encoded digest supplied by the sender (case-insensitive).

  Returns `:ok` when the signature matches, `:error` otherwise.
  """
  @spec verify(binary(), binary() | nil, binary()) :: :ok | :error
  def verify(payload, signature, secret)
      when is_binary(payload) and is_binary(signature) and is_binary(secret) do
    expected = :crypto.mac(:hmac, :sha256, secret, payload) |> Base.encode16(case: :lower)
    given = String.downcase(signature)

    if secure_compare(expected, given), do: :ok, else: :error
  end

  def verify(_payload, _signature, _secret), do: :error

  @spec secure_compare(binary(), binary()) :: boolean()
  defp secure_compare(left, right) when byte_size(left) == byte_size(right) do
    :crypto.hash_equals(left, right)
  end

  defp secure_compare(_left, _right), do: false
end

defmodule WebhookReceiver.Store do
  @moduledoc """
  Behaviour for webhook event storage backends, plus client functions that
  dispatch to a running store process.

  Implementations are process-backed: every callback takes the pid (or any
  `t:GenServer.server/0`) of an already-started store as its first argument.
  The client functions defined here forward to that process via
  `GenServer.call/2`, so callers can use `WebhookReceiver.Store.get_event/2`
  without knowing which backend is in play.
  """

  @typedoc "A stored webhook event."
  @type event :: %{
          required(:event_id) => String.t(),
          required(:payload) => map(),
          required(:status) => :pending,
          optional(atom()) => term()
        }

  @typedoc "A running store process."
  @type store :: GenServer.server()

  @doc """
  Persists `payload` under `event_id` with status `:pending`.

  Returns `{:ok, :created}` for a new event and `{:ok, :duplicate}` when
  `event_id` has already been stored (the existing event is left untouched).
  """
  @callback store_event(store(), String.t(), map()) :: {:ok, :created | :duplicate}

  @doc """
  Fetches the event stored under `event_id`.

  Returns `{:ok, event}` or `:error` if no such event exists.
  """
  @callback get_event(store(), String.t()) :: {:ok, event()} | :error

  @doc """
  Returns every stored event as a list.
  """
  @callback all_events(store()) :: [event()]

  @doc """
  Persists `payload` under `event_id` with status `:pending` in `store`.

  Returns `{:ok, :created}` for a new event, `{:ok, :duplicate}` if `event_id`
  was already stored.
  """
  @spec store_event(store(), String.t(), map()) :: {:ok, :created | :duplicate}
  def store_event(store, event_id, payload) when is_binary(event_id) and is_map(payload) do
    GenServer.call(store, {:store_event, event_id, payload})
  end

  @doc """
  Fetches the event stored under `event_id` from `store`.

  Returns `{:ok, event}` or `:error`.
  """
  @spec get_event(store(), String.t()) :: {:ok, event()} | :error
  def get_event(store, event_id) when is_binary(event_id) do
    GenServer.call(store, {:get_event, event_id})
  end

  @doc """
  Returns every event held by `store` as a list.
  """
  @spec all_events(store()) :: [event()]
  def all_events(store) do
    GenServer.call(store, :all_events)
  end
end

defmodule WebhookReceiver.MemoryStore do
  @moduledoc """
  In-memory `WebhookReceiver.Store` implementation backed by a `GenServer`
  holding a map of `event_id => event`.

  Intended for tests and single-node development: state lives only in the
  process heap and is lost when the process stops.

      {:ok, store} = WebhookReceiver.MemoryStore.start_link([])
      {:ok, :created} = WebhookReceiver.Store.store_event(store, "evt_1", %{"id" => "evt_1"})
      {:ok, :duplicate} = WebhookReceiver.Store.store_event(store, "evt_1", %{"id" => "evt_1"})
  """

  @behaviour WebhookReceiver.Store

  use GenServer

  alias WebhookReceiver.Store

  @doc """
  Starts the store.

  Accepts the usual `GenServer` options (`:name`, `:timeout`, …); all other
  options are ignored. The store begins empty.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {server_opts, _rest} = Keyword.split(opts, [:name, :timeout, :debug, :spawn_opt, :hibernate_after])

    GenServer.start_link(__MODULE__, :ok, server_opts)
  end

  @doc """
  Persists `payload` under `event_id` with status `:pending`.

  Returns `{:ok, :created}` for a new event, `{:ok, :duplicate}` otherwise.
  """
  @impl WebhookReceiver.Store
  @spec store_event(Store.store(), String.t(), map()) :: {:ok, :created | :duplicate}
  def store_event(store, event_id, payload), do: Store.store_event(store, event_id, payload)

  @doc """
  Fetches the event stored under `event_id`. Returns `{:ok, event}` or `:error`.
  """
  @impl WebhookReceiver.Store
  @spec get_event(Store.store(), String.t()) :: {:ok, Store.event()} | :error
  def get_event(store, event_id), do: Store.get_event(store, event_id)

  @doc """
  Returns every stored event as a list.
  """
  @impl WebhookReceiver.Store
  @spec all_events(Store.store()) :: [Store.event()]
  def all_events(store), do: Store.all_events(store)

  @impl GenServer
  def init(:ok), do: {:ok, %{}}

  @impl GenServer
  def handle_call({:store_event, event_id, payload}, _from, events) do
    case Map.fetch(events, event_id) do
      {:ok, _existing} ->
        {:reply, {:ok, :duplicate}, events}

      :error ->
        event = %{event_id: event_id, payload: payload, status: :pending}
        {:reply, {:ok, :created}, Map.put(events, event_id, event)}
    end
  end

  def handle_call({:get_event, event_id}, _from, events) do
    {:reply, Map.fetch(events, event_id), events}
  end

  def handle_call(:all_events, _from, events) do
    {:reply, Map.values(events), events}
  end
end

defmodule WebhookReceiver.Router do
  @moduledoc """
  `Plug.Router` exposing `POST /api/webhooks/stripe`.

  The router is initialised with two options:

    * `:secret` — the HMAC-SHA256 signing key shared with the sender.
    * `:store` — the **pid** of an already-started `WebhookReceiver.Store`
      process (e.g. `WebhookReceiver.MemoryStore`).

  Usage:

      {:ok, store} = WebhookReceiver.MemoryStore.start_link([])
      opts = WebhookReceiver.Router.init(secret: "s3cr3t", store: store)
      WebhookReceiver.Router.call(conn, opts)

  Behaviour of the endpoint:

    * missing `stripe-signature` header, or a signature that does not verify
      against the raw body → `401 {"error": "invalid_signature"}`
    * malformed JSON, a non-object body, or a body without a binary `"id"`
      → `400 {"error": "bad_payload"}`
    * a body whose `"id"` was already stored → `200 {"status": "duplicate"}`
    * otherwise the event is stored with status `:pending`
      → `200 {"status": "received"}`

  The raw body is read once by `WebhookReceiver.Router.CacheBodyReader` and
  stashed in `conn.assigns[:raw_body]` so it is available verbatim for
  signature verification while `Plug.Parsers` still decodes the JSON.
  """

  use Plug.Router, copy_opts_to_assign: :webhook_opts

  alias WebhookReceiver.Signature
  alias WebhookReceiver.Store

  defmodule CacheBodyReader do
    @moduledoc """
    Body reader for `Plug.Parsers` that caches the raw request body in
    `conn.assigns[:raw_body]` as it is streamed to the parser.
    """

    @doc """
    Reads a chunk of the request body and appends it to `conn.assigns[:raw_body]`.

    Conforms to the `Plug.Parsers` `:body_reader` contract and delegates the
    actual reading to `Plug.Conn.read_body/2`.
    """
    @spec read_body(Plug.Conn.t(), keyword()) ::
            {:ok, binary(), Plug.Conn.t()}
            | {:more, binary(), Plug.Conn.t()}
            | {:error, term()}
    def read_body(conn, opts \\ []) do
      case Plug.Conn.read_body(conn, opts) do
        {:ok, body, conn} -> {:ok, body, cache(conn, body)}
        {:more, body, conn} -> {:more, body, cache(conn, body)}
        {:error, reason} -> {:error, reason}
      end
    end

    @spec cache(Plug.Conn.t(), binary()) :: Plug.Conn.t()
    defp cache(conn, chunk) do
      Plug.Conn.assign(conn, :raw_body, Map.get(conn.assigns, :raw_body, "") <> chunk)
    end
  end

  plug :match

  plug Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    body_reader: {CacheBodyReader, :read_body, []},
    json_decoder: Jason

  plug :dispatch

  @doc """
  Builds the router options passed to `call/2`.

  Expects `:secret` (a binary HMAC key) and `:store` (the pid of a running
  store process); both are carried through to `conn.assigns[:webhook_opts]`.
  """
  @spec init(keyword()) :: keyword()
  def init(opts) do
    opts
    |> super()
    |> validate_opts()
  end

  post "/api/webhooks/stripe" do
    opts = conn.assigns[:webhook_opts]
    secret = fetch_opt(opts, :secret)
    store = fetch_opt(opts, :store)
    {conn, raw_body} = raw_body(conn)

    with :ok <- verify_signature(conn, raw_body, secret),
         {:ok, event_id, payload} <- extract_event(raw_body) do
      case Store.store_event(store, event_id, payload) do
        {:ok, :duplicate} -> send_json(conn, 200, %{status: "duplicate"})
        {:ok, :created} -> send_json(conn, 200, %{status: "received"})
      end
    else
      :invalid_signature -> send_json(conn, 401, %{error: "invalid_signature"})
      :bad_payload -> send_json(conn, 400, %{error: "bad_payload"})
    end
  end

  match _ do
    send_json(conn, 404, %{error: "not_found"})
  end

  @spec validate_opts(keyword()) :: keyword()
  defp validate_opts(opts) do
    for key <- [:secret, :store], not Keyword.has_key?(opts, key) do
      raise ArgumentError, "WebhookReceiver.Router requires the #{inspect(key)} option"
    end

    opts
  end

  @spec fetch_opt(keyword() | map() | nil, atom()) :: term()
  defp fetch_opt(opts, key) when is_list(opts), do: Keyword.fetch!(opts, key)
  defp fetch_opt(opts, key) when is_map(opts), do: Map.fetch!(opts, key)

  @spec raw_body(Plug.Conn.t()) :: {Plug.Conn.t(), binary()}
  defp raw_body(%Plug.Conn{assigns: %{raw_body: body}} = conn), do: {conn, body}

  defp raw_body(conn) do
    case Plug.Conn.read_body(conn, length: 1_000_000) do
      {:ok, body, conn} -> {Plug.Conn.assign(conn, :raw_body, body), body}
      {:more, body, conn} -> {Plug.Conn.assign(conn, :raw_body, body), body}
      {:error, _reason} -> {conn, ""}
    end
  end

  @spec verify_signature(Plug.Conn.t(), binary(), binary()) :: :ok | :invalid_signature
  defp verify_signature(conn, raw_body, secret) do
    case Plug.Conn.get_req_header(conn, "stripe-signature") do
      [signature | _rest] ->
        case Signature.verify(raw_body, signature, secret) do
          :ok -> :ok
          :error -> :invalid_signature
        end

      [] ->
        :invalid_signature
    end
  end

  @spec extract_event(binary()) :: {:ok, String.t(), map()} | :bad_payload
  defp extract_event(raw_body) do
    with {:ok, payload} when is_map(payload) <- Jason.decode(raw_body),
         {:ok, event_id} when is_binary(event_id) <- Map.fetch(payload, "id") do
      {:ok, event_id, payload}
    else
      _other -> :bad_payload
    end
  end

  @spec send_json(Plug.Conn.t(), non_neg_integer(), map()) :: Plug.Conn.t()
  defp send_json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end
end