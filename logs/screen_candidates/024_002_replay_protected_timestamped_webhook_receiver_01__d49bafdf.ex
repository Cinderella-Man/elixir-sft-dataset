defmodule WebhookReceiver.Signature do
  @moduledoc """
  Helpers for computing and parsing Stripe-style timestamped HMAC-SHA256 webhook signatures.

  A signature header looks like `t=1700000000,v1=<hex>` where `<hex>` is the lowercase
  hex-encoded HMAC-SHA256 of the string `"<timestamp>.<payload>"` keyed by the shared secret.
  """

  @doc """
  Computes the lowercase hex-encoded HMAC-SHA256 of `"<timestamp>.<payload>"` using `secret`.

  The `timestamp` may be given as an integer or a binary; both produce the same signature.
  """
  @spec sign(integer() | binary(), binary(), binary()) :: binary()
  def sign(timestamp, payload, secret)
      when is_binary(payload) and is_binary(secret) do
    signed_payload = "#{timestamp}.#{payload}"

    :crypto.mac(:hmac, :sha256, secret, signed_payload)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Parses a signature header such as `"t=1700000000,v1=abc"` into a map of field to value.

  Unknown fields are preserved. Entries without an `=` separator are ignored. Any input that
  is not a binary yields `%{}`.
  """
  @spec parse(term()) :: %{optional(binary()) => binary()}
  def parse(header) when is_binary(header) do
    header
    |> String.split(",")
    |> Enum.reduce(%{}, fn part, acc ->
      case String.split(String.trim(part), "=", parts: 2) do
        [key, value] when key != "" -> Map.put(acc, key, value)
        _other -> acc
      end
    end)
  end

  def parse(_header), do: %{}
end

defmodule WebhookReceiver.Store do
  @moduledoc """
  Behaviour describing a webhook event store, plus client functions dispatching to a store
  process.

  Implementations persist events keyed by their event id. Each stored event is a map holding
  at least `:event_id`, `:payload` (the decoded JSON map) and `:status` (`:pending` when
  freshly created).
  """

  @typedoc "The store process: a pid or a registered name."
  @type store :: GenServer.server()

  @typedoc "A persisted webhook event."
  @type event :: %{
          required(:event_id) => binary(),
          required(:payload) => map(),
          required(:status) => atom()
        }

  @callback store_event(store(), binary(), map()) :: {:ok, :created} | {:ok, :duplicate}
  @callback get_event(store(), binary()) :: {:ok, event()} | :error
  @callback all_events(store()) :: [event()]

  @doc """
  Stores `payload` under `event_id` with status `:pending`.

  Returns `{:ok, :created}` when the id was previously unknown and `{:ok, :duplicate}` when an
  event with the same id already exists (in which case the stored event is left untouched).
  """
  @spec store_event(store(), binary(), map()) :: {:ok, :created} | {:ok, :duplicate}
  def store_event(store, event_id, payload) when is_binary(event_id) and is_map(payload) do
    GenServer.call(store, {:store_event, event_id, payload})
  end

  @doc """
  Fetches the event stored under `event_id`, returning `{:ok, event}` or `:error`.
  """
  @spec get_event(store(), binary()) :: {:ok, event()} | :error
  def get_event(store, event_id) when is_binary(event_id) do
    GenServer.call(store, {:get_event, event_id})
  end

  @doc """
  Returns every stored event as a list, in unspecified order.
  """
  @spec all_events(store()) :: [event()]
  def all_events(store) do
    GenServer.call(store, :all_events)
  end
end

defmodule WebhookReceiver.MemoryStore do
  @moduledoc """
  An in-memory `WebhookReceiver.Store` implementation backed by a `GenServer` holding a map.

  Intended for tests and single-node development; state is lost when the process stops.
  """

  @behaviour WebhookReceiver.Store

  use GenServer

  @doc """
  Starts the store. Accepts the usual `GenServer` options such as `:name`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {gen_opts, _rest} = Keyword.split(opts, [:name, :timeout, :debug, :spawn_opt, :hibernate_after])
    GenServer.start_link(__MODULE__, :ok, gen_opts)
  end

  @doc """
  Stores `payload` under `event_id` with status `:pending`. See `WebhookReceiver.Store`.
  """
  @impl WebhookReceiver.Store
  @spec store_event(GenServer.server(), binary(), map()) :: {:ok, :created} | {:ok, :duplicate}
  def store_event(store, event_id, payload) do
    WebhookReceiver.Store.store_event(store, event_id, payload)
  end

  @doc """
  Fetches the event stored under `event_id`. See `WebhookReceiver.Store`.
  """
  @impl WebhookReceiver.Store
  @spec get_event(GenServer.server(), binary()) :: {:ok, WebhookReceiver.Store.event()} | :error
  def get_event(store, event_id) do
    WebhookReceiver.Store.get_event(store, event_id)
  end

  @doc """
  Returns all stored events. See `WebhookReceiver.Store`.
  """
  @impl WebhookReceiver.Store
  @spec all_events(GenServer.server()) :: [WebhookReceiver.Store.event()]
  def all_events(store) do
    WebhookReceiver.Store.all_events(store)
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
  A `Plug.Router` exposing `POST /api/webhooks/stripe` for replay-protected webhook delivery.

  Options (given to `init/1`, i.e. when plugging the router):

    * `:secret` — the HMAC signing key (required)
    * `:store` — the store process, a pid or registered name (required)
    * `:tolerance` — maximum allowed clock skew in seconds (default `300`)
    * `:now` — an integer Unix timestamp in seconds, or a 0-arity function returning one,
      used as the current time (default `System.system_time(:second)`)

  Requests must carry a `stripe-signature` header of the form `t=<unix>,v1=<hex>`. Invalid or
  unverifiable signatures yield `401 {"error": "invalid_signature"}`; valid signatures outside
  the tolerance window yield `401 {"error": "timestamp_expired"}`. Payloads that are not JSON
  objects carrying an `"id"` yield `400 {"error": "bad_payload"}`.
  """

  use Plug.Router

  alias WebhookReceiver.Signature
  alias WebhookReceiver.Store

  @default_tolerance 300

  plug(:match)
  plug(:dispatch)

  @doc """
  Validates and normalises the router options. See the module documentation.
  """
  @spec init(keyword()) :: map()
  def init(opts) do
    %{
      secret: Keyword.fetch!(opts, :secret),
      store: Keyword.fetch!(opts, :store),
      tolerance: Keyword.get(opts, :tolerance, @default_tolerance),
      now: Keyword.get(opts, :now)
    }
  end

  @doc """
  Dispatches the connection through the router with the normalised `opts`.
  """
  @spec call(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def call(conn, opts) do
    conn
    |> put_private(:webhook_receiver, opts)
    |> super(opts)
  end

  post "/api/webhooks/stripe" do
    opts = conn.private[:webhook_receiver]
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    header = conn |> get_req_header("stripe-signature") |> List.first()

    case verify(header, body, opts) do
      :ok -> handle_payload(conn, body, opts)
      {:error, reason} -> send_json(conn, 401, %{"error" => Atom.to_string(reason)})
    end
  end

  match _ do
    send_json(conn, 404, %{"error" => "not_found"})
  end

  @spec verify(binary() | nil, binary(), map()) ::
          :ok | {:error, :invalid_signature | :timestamp_expired}
  defp verify(header, body, opts) do
    fields = Signature.parse(header)

    with {:ok, raw_timestamp} <- fetch_present(fields, "t"),
         {:ok, provided} <- fetch_present(fields, "v1"),
         {timestamp, ""} <- Integer.parse(raw_timestamp),
         :ok <- check_tolerance(timestamp, opts) do
      expected = Signature.sign(raw_timestamp, body, opts.secret)

      if secure_compare(expected, provided) do
        :ok
      else
        {:error, :invalid_signature}
      end
    else
      {:error, reason} -> {:error, reason}
      _other -> {:error, :invalid_signature}
    end
  end

  @spec fetch_present(map(), binary()) :: {:ok, binary()} | :error
  defp fetch_present(fields, key) do
    case Map.get(fields, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> :error
    end
  end

  @spec check_tolerance(integer(), map()) :: :ok | {:error, :timestamp_expired}
  defp check_tolerance(timestamp, opts) do
    if abs(current_time(opts) - timestamp) > opts.tolerance do
      {:error, :timestamp_expired}
    else
      :ok
    end
  end

  @spec current_time(map()) :: integer()
  defp current_time(%{now: now}) when is_integer(now), do: now
  defp current_time(%{now: now}) when is_function(now, 0), do: now.()
  defp current_time(_opts), do: System.system_time(:second)

  @spec secure_compare(binary(), binary()) :: boolean()
  defp secure_compare(left, right) when byte_size(left) == byte_size(right) do
    :crypto.hash_equals(left, right)
  end

  defp secure_compare(_left, _right), do: false

  @spec handle_payload(Plug.Conn.t(), binary(), map()) :: Plug.Conn.t()
  defp handle_payload(conn, body, opts) do
    with {:ok, payload} when is_map(payload) <- Jason.decode(body),
         {:ok, event_id} when is_binary(event_id) <- Map.fetch(payload, "id") do
      case Store.store_event(opts.store, event_id, payload) do
        {:ok, :duplicate} -> send_json(conn, 200, %{"status" => "duplicate"})
        {:ok, :created} -> send_json(conn, 200, %{"status" => "received"})
      end
    else
      _other -> send_json(conn, 400, %{"error" => "bad_payload"})
    end
  end

  @spec send_json(Plug.Conn.t(), pos_integer(), map()) :: Plug.Conn.t()
  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end

defmodule WebhookReceiver do
  @moduledoc """
  Entry point for the webhook receiver: a Plug-based endpoint that accepts Stripe-style
  timestamped HMAC-SHA256 signed payloads and records them, ignoring replays.

  See `WebhookReceiver.Router` for the HTTP contract, `WebhookReceiver.Signature` for the
  signing scheme and `WebhookReceiver.Store` for the persistence behaviour.
  """

  @doc """
  Returns the signature header value a client should send for `payload` at `timestamp`.

  Useful for tests and for clients that need to produce a valid `stripe-signature` header.
  """
  @spec signature_header(integer(), binary(), binary()) :: binary()
  def signature_header(timestamp, payload, secret)
      when is_integer(timestamp) and is_binary(payload) and is_binary(secret) do
    "t=#{timestamp},v1=#{WebhookReceiver.Signature.sign(timestamp, payload, secret)}"
  end
end