defmodule WebhookReceiver do
  @moduledoc """
  A small, Plug-based webhook receiver that validates replay-protected,
  timestamped HMAC-SHA256 signatures (the Stripe `t=...,v1=...` scheme).

  The pieces are:

    * `WebhookReceiver.Signature` — signing and header parsing helpers.
    * `WebhookReceiver.Store` — behaviour (and client API) for event storage.
    * `WebhookReceiver.MemoryStore` — a `GenServer` implementation of the behaviour.
    * `WebhookReceiver.Router` — a `Plug.Router` exposing `POST /api/webhooks/stripe`.

  Only `:plug`, `:jason` and OTP's `:crypto` are required — no Phoenix, no Ecto.
  """
end

defmodule WebhookReceiver.Signature do
  @moduledoc """
  Computes and parses Stripe-style webhook signatures.

  A signature header looks like:

      t=1700000000,v1=5257a869e7ecebeda32affa62cdca3fa51cad7e77a0e56ff536d0ce8e108d8bd

  where `v1` is the lowercase hex-encoded HMAC-SHA256 of the *signed payload*
  string `"<timestamp>.<raw body>"`, keyed with the endpoint's signing secret.
  """

  @doc """
  Computes the lowercase hex-encoded HMAC-SHA256 of `"<timestamp>.<payload>"`.

  `timestamp` may be an integer or a binary; `payload` and `secret` are binaries.

  ## Examples

      iex> WebhookReceiver.Signature.sign(1_700_000_000, "{}", "whsec_test") ==
      ...>   WebhookReceiver.Signature.sign("1700000000", "{}", "whsec_test")
      true

  """
  @spec sign(integer() | binary(), binary(), binary()) :: binary()
  def sign(timestamp, payload, secret)
      when (is_integer(timestamp) or is_binary(timestamp)) and is_binary(payload) and
             is_binary(secret) do
    signed_payload = signed_payload(timestamp, payload)

    :hmac
    |> :crypto.mac(:sha256, secret, signed_payload)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Parses a signature header into a map of its comma-separated `key=value` pairs.

  Unknown schemes are preserved, malformed elements are ignored, and anything that
  is not a binary yields an empty map.

  ## Examples

      iex> WebhookReceiver.Signature.parse("t=1700000000,v1=abc")
      %{"t" => "1700000000", "v1" => "abc"}

      iex> WebhookReceiver.Signature.parse(nil)
      %{}

  """
  @spec parse(term()) :: %{optional(binary()) => binary()}
  def parse(header) when is_binary(header) do
    header
    |> String.split(",")
    |> Enum.reduce(%{}, fn element, acc ->
      case String.split(String.trim(element), "=", parts: 2) do
        [key, value] when key != "" -> Map.put_new(acc, key, value)
        _other -> acc
      end
    end)
  end

  def parse(_header), do: %{}

  @spec signed_payload(integer() | binary(), binary()) :: binary()
  defp signed_payload(timestamp, payload) when is_integer(timestamp) do
    signed_payload(Integer.to_string(timestamp), payload)
  end

  defp signed_payload(timestamp, payload) when is_binary(timestamp) do
    timestamp <> "." <> payload
  end
end

defmodule WebhookReceiver.Store do
  @moduledoc """
  Behaviour for webhook event stores, plus the client API used to talk to them.

  Implementations are expected to be processes (a `GenServer`, typically): every
  callback takes the store process as its first argument. The functions defined in
  this module simply dispatch to that process, so callers may use either
  `WebhookReceiver.Store.get_event(store, id)` or the implementation module
  directly.
  """

  @typedoc "A store process: pid, registered name, or any `GenServer.server()`."
  @type store :: GenServer.server()

  @typedoc "The webhook event identifier (the `\"id\"` field of the payload)."
  @type event_id :: binary()

  @typedoc "A decoded JSON webhook payload."
  @type payload :: map()

  @typedoc "A stored event record."
  @type event :: %{
          required(:event_id) => event_id(),
          required(:payload) => payload(),
          required(:status) => atom(),
          optional(atom()) => term()
        }

  @doc "Persists `payload` under `event_id` with status `:pending`."
  @callback store_event(store(), event_id(), payload()) :: {:ok, :created | :duplicate}

  @doc "Fetches the event stored under `event_id`."
  @callback get_event(store(), event_id()) :: {:ok, event()} | :error

  @doc "Returns every stored event."
  @callback all_events(store()) :: [event()]

  @doc """
  Stores `payload` under `event_id` with status `:pending`.

  Returns `{:ok, :created}` for a new id and `{:ok, :duplicate}` when the id has
  already been stored (the existing event is left untouched).
  """
  @spec store_event(store(), event_id(), payload()) :: {:ok, :created | :duplicate}
  def store_event(store, event_id, payload) when is_binary(event_id) and is_map(payload) do
    GenServer.call(store, {:store_event, event_id, payload})
  end

  @doc """
  Returns `{:ok, event}` when `event_id` is known, `:error` otherwise.
  """
  @spec get_event(store(), event_id()) :: {:ok, event()} | :error
  def get_event(store, event_id) when is_binary(event_id) do
    GenServer.call(store, {:get_event, event_id})
  end

  @doc """
  Returns all stored events as a list.
  """
  @spec all_events(store()) :: [event()]
  def all_events(store) do
    GenServer.call(store, :all_events)
  end
end

defmodule WebhookReceiver.MemoryStore do
  @moduledoc """
  An in-memory `WebhookReceiver.Store` backed by a `GenServer` holding a map of
  `event_id => event`.

  Events are stored as maps with `:event_id`, `:payload` (the decoded JSON body)
  and `:status` (always `:pending` at creation time). Storing an id twice is a
  no-op that reports `{:ok, :duplicate}`, which is what gives the receiver its
  idempotency guarantee.
  """

  use GenServer

  @behaviour WebhookReceiver.Store

  alias WebhookReceiver.Store

  @doc """
  Starts the store.

  All options are forwarded to `GenServer.start_link/3`, so `:name` works as usual.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @doc """
  Stores `payload` under `event_id` with status `:pending`.

  See `WebhookReceiver.Store.store_event/3`.
  """
  @impl WebhookReceiver.Store
  @spec store_event(Store.store(), Store.event_id(), Store.payload()) ::
          {:ok, :created | :duplicate}
  def store_event(store, event_id, payload) do
    GenServer.call(store, {:store_event, event_id, payload})
  end

  @doc """
  Fetches the event stored under `event_id`, or `:error` if there is none.
  """
  @impl WebhookReceiver.Store
  @spec get_event(Store.store(), Store.event_id()) :: {:ok, Store.event()} | :error
  def get_event(store, event_id) do
    GenServer.call(store, {:get_event, event_id})
  end

  @doc """
  Returns every stored event as a list.
  """
  @impl WebhookReceiver.Store
  @spec all_events(Store.store()) :: [Store.event()]
  def all_events(store) do
    GenServer.call(store, :all_events)
  end

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
  A `Plug.Router` exposing `POST /api/webhooks/stripe`.

  ## Options

    * `:secret` — the HMAC signing key (required).
    * `:store` — the store process implementing `WebhookReceiver.Store` (required).
    * `:tolerance` — maximum allowed clock skew, in seconds (default `300`).
    * `:now` — an integer Unix timestamp (seconds) or a 0-arity function returning
      one, used as the current time (default `System.system_time(:second)`).

  ## Responses

    * `401 {"error":"invalid_signature"}` — header missing, unparseable, or the
      computed HMAC does not match.
    * `401 {"error":"timestamp_expired"}` — `abs(now - t) > tolerance`. Checked
      before any signature mismatch is reported.
    * `400 {"error":"bad_payload"}` — body is not JSON or has no `"id"` field.
    * `200 {"status":"received"}` — new event, stored with status `:pending`.
    * `200 {"status":"duplicate"}` — the event id was already stored.

  The raw request body is read exactly once and used both for signature
  verification and for JSON decoding.
  """

  use Plug.Router

  alias WebhookReceiver.Signature
  alias WebhookReceiver.Store

  @default_tolerance 300
  @private_key :webhook_receiver_opts

  plug :match
  plug :dispatch

  @doc """
  Validates and normalizes the router options into the configuration map used at
  request time. Raises if `:secret` or `:store` is missing.
  """
  @impl Plug
  @spec init(keyword()) :: map()
  def init(opts) do
    %{
      secret: Keyword.fetch!(opts, :secret),
      store: Keyword.fetch!(opts, :store),
      tolerance: Keyword.get(opts, :tolerance, @default_tolerance),
      now: Keyword.get(opts, :now, &__MODULE__.system_now/0)
    }
  end

  @doc """
  Stashes the configuration on the connection and runs the router pipeline.
  """
  @impl Plug
  @spec call(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def call(conn, opts) do
    conn
    |> put_private(@private_key, opts)
    |> super(opts)
  end

  @doc """
  Returns the current Unix time in seconds. Default value of the `:now` option.
  """
  @spec system_now() :: integer()
  def system_now, do: System.system_time(:second)

  post "/api/webhooks/stripe" do
    config = Map.fetch!(conn.private, @private_key)

    case read_full_body(conn, "") do
      {:ok, raw_body, conn} -> handle_webhook(conn, raw_body, config)
      {:error, _reason} -> send_json(conn, 400, %{"error" => "bad_payload"})
    end
  end

  match _ do
    send_json(conn, 404, %{"error" => "not_found"})
  end

  @spec handle_webhook(Plug.Conn.t(), binary(), map()) :: Plug.Conn.t()
  defp handle_webhook(conn, raw_body, config) do
    with {:ok, timestamp, signature} <- signature_parts(conn),
         :ok <- verify_timestamp(timestamp, config),
         :ok <- verify_signature(timestamp, raw_body, signature, config),
         {:ok, event_id, payload} <- decode_payload(raw_body) do
      store_event(conn, config, event_id, payload)
    else
      {:error, :timestamp_expired} -> send_json(conn, 401, %{"error" => "timestamp_expired"})
      {:error, :bad_payload} -> send_json(conn, 400, %{"error" => "bad_payload"})
      {:error, :invalid_signature} -> send_json(conn, 401, %{"error" => "invalid_signature"})
    end
  end

  @spec store_event(Plug.Conn.t(), map(), binary(), map()) :: Plug.Conn.t()
  defp store_event(conn, config, event_id, payload) do
    case Store.store_event(config.store, event_id, payload) do
      {:ok, :duplicate} -> send_json(conn, 200, %{"status" => "duplicate"})
      {:ok, :created} -> send_json(conn, 200, %{"status" => "received"})
    end
  end

  @spec signature_parts(Plug.Conn.t()) ::
          {:ok, integer(), binary()} | {:error, :invalid_signature}
  defp signature_parts(conn) do
    with [header | _rest] <- get_req_header(conn, "stripe-signature"),
         %{"t" => raw_timestamp, "v1" => signature} <- Signature.parse(header),
         false <- signature == "",
         {timestamp, ""} <- Integer.parse(raw_timestamp) do
      {:ok, timestamp, signature}
    else
      _other -> {:error, :invalid_signature}
    end
  end

  @spec verify_timestamp(integer(), map()) :: :ok | {:error, :timestamp_expired}
  defp verify_timestamp(timestamp, config) do
    if abs(current_time(config) - timestamp) > config.tolerance do
      {:error, :timestamp_expired}
    else
      :ok
    end
  end

  @spec verify_signature(integer(), binary(), binary(), map()) ::
          :ok | {:error, :invalid_signature}
  defp verify_signature(timestamp, raw_body, signature, config) do
    expected = Signature.sign(timestamp, raw_body, config.secret)

    if Plug.Crypto.secure_compare(expected, String.downcase(signature)) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  @spec decode_payload(binary()) :: {:ok, binary(), map()} | {:error, :bad_payload}
  defp decode_payload(raw_body) do
    case Jason.decode(raw_body) do
      {:ok, %{"id" => id} = payload} when is_binary(id) and id != "" ->
        {:ok, id, payload}

      {:ok, %{"id" => id} = payload} when is_integer(id) ->
        {:ok, Integer.to_string(id), payload}

      _other ->
        {:error, :bad_payload}
    end
  end

  @spec current_time(map()) :: integer()
  defp current_time(%{now: now}) when is_integer(now), do: now
  defp current_time(%{now: now}) when is_function(now, 0), do: now.()

  @spec read_full_body(Plug.Conn.t(), binary()) ::
          {:ok, binary(), Plug.Conn.t()} | {:error, term()}
  defp read_full_body(conn, acc) do
    case read_body(conn) do
      {:ok, chunk, conn} -> {:ok, acc <> chunk, conn}
      {:more, chunk, conn} -> read_full_body(conn, acc <> chunk)
      {:error, reason} -> {:error, reason}
    end
  end

  @spec send_json(Plug.Conn.t(), 200..599, map()) :: Plug.Conn.t()
  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
    |> halt()
  end
end