defmodule WebhookReceiver.Signature do
  @moduledoc """
  HMAC-SHA256 signature verification helpers for inbound webhooks.

  Signatures are compared in constant time to avoid leaking information through
  timing side channels. Providers frequently prefix the hex digest with a scheme
  marker (for example `"sha256="`), which is supported through the `prefix`
  argument.

  `verify_any/4` supports secret rotation: a provider may have several
  simultaneously-valid secrets, and a payload is accepted when it matches any of
  them.
  """

  @doc """
  Verifies `signature` against the HMAC-SHA256 of `payload` computed with `secret`.

  The expected value is `prefix <> Base.encode16(hmac, case: :lower)`. Returns
  `:ok` on a match and `:error` otherwise. Any non-binary argument yields `:error`.
  """
  @spec verify(binary(), binary(), binary(), binary()) :: :ok | :error
  def verify(payload, signature, secret, prefix \\ "")

  def verify(payload, signature, secret, prefix)
      when is_binary(payload) and is_binary(signature) and is_binary(secret) and
             is_binary(prefix) do
    expected = prefix <> hex_digest(payload, secret)

    if secure_compare(expected, signature), do: :ok, else: :error
  end

  def verify(_payload, _signature, _secret, _prefix), do: :error

  @doc """
  Verifies `signature` against `payload` for each secret in `secrets`.

  Returns `:ok` as soon as one secret matches, `:error` when none do (including
  when `secrets` is empty or not a list).
  """
  @spec verify_any(binary(), binary(), [binary()], binary()) :: :ok | :error
  def verify_any(payload, signature, secrets, prefix \\ "")

  def verify_any(payload, signature, secrets, prefix) when is_list(secrets) do
    matched? =
      Enum.reduce(secrets, false, fn secret, acc ->
        # No short-circuit: every candidate secret is checked so that verification
        # time does not depend on which secret (if any) matched.
        verify(payload, signature, secret, prefix) == :ok or acc
      end)

    if matched?, do: :ok, else: :error
  end

  def verify_any(_payload, _signature, _secrets, _prefix), do: :error

  @doc """
  Returns the lowercase hex HMAC-SHA256 digest of `payload` keyed with `secret`.
  """
  @spec hex_digest(binary(), binary()) :: binary()
  def hex_digest(payload, secret) when is_binary(payload) and is_binary(secret) do
    :crypto.mac(:hmac, :sha256, secret, payload) |> Base.encode16(case: :lower)
  end

  @doc """
  Compares two binaries in constant time relative to their contents.

  Returns `true` when the binaries are byte-for-byte equal, `false` otherwise.
  """
  @spec secure_compare(binary(), binary()) :: boolean()
  def secure_compare(left, right) when is_binary(left) and is_binary(right) do
    if byte_size(left) == byte_size(right) do
      crypto_equal?(left, right)
    else
      # Still run a comparison against `left` so the failure path does work
      # proportional to the input rather than returning immediately.
      _ = crypto_equal?(left, left)
      false
    end
  end

  @spec crypto_equal?(binary(), binary()) :: boolean()
  defp crypto_equal?(left, right) do
    :crypto.hash_equals(left, right)
  rescue
    ArgumentError -> false
  end
end

defmodule WebhookReceiver.Store do
  @moduledoc """
  Behaviour for webhook event stores, plus the client API used to talk to a store
  process.

  Events are keyed by the `{provider, event_id}` pair, so two providers may emit
  the same event id without colliding. Implementations are expected to be
  processes (a `GenServer` or anything answering the same `GenServer.call/2`
  messages); the functions in this module dispatch to `store` for callers.
  """

  @typedoc "A running store process."
  @type store :: GenServer.server()

  @typedoc "Provider name, taken from the request path."
  @type provider :: String.t()

  @typedoc "Provider-scoped unique id of a webhook event."
  @type event_id :: String.t()

  @typedoc "A stored webhook event."
  @type event :: %{
          required(:provider) => provider(),
          required(:event_id) => event_id(),
          required(:payload) => map(),
          required(:status) => :pending,
          optional(atom()) => term()
        }

  @callback store_event(store(), provider(), event_id(), map()) ::
              {:ok, :created} | {:ok, :duplicate}
  @callback get_event(store(), provider(), event_id()) :: {:ok, event()} | :error
  @callback all_events(store()) :: [event()]

  @doc """
  Stores `payload` under `{provider, event_id}` with status `:pending`.

  Returns `{:ok, :created}` for a new event and `{:ok, :duplicate}` when the
  provider/id pair is already known. Duplicates never overwrite the stored event.
  """
  @spec store_event(store(), provider(), event_id(), map()) ::
          {:ok, :created} | {:ok, :duplicate}
  def store_event(store, provider, event_id, payload) do
    GenServer.call(store, {:store_event, provider, event_id, payload})
  end

  @doc """
  Fetches the event stored for `{provider, event_id}`.

  Returns `{:ok, event}` when present and `:error` when it is unknown.
  """
  @spec get_event(store(), provider(), event_id()) :: {:ok, event()} | :error
  def get_event(store, provider, event_id) do
    GenServer.call(store, {:get_event, provider, event_id})
  end

  @doc """
  Returns every event currently held by `store`, as a list.
  """
  @spec all_events(store()) :: [event()]
  def all_events(store) do
    GenServer.call(store, :all_events)
  end
end

defmodule WebhookReceiver.MemoryStore do
  @moduledoc """
  In-memory `WebhookReceiver.Store` implementation backed by a `GenServer`.

  State is a map keyed by `{provider, event_id}`, so the same event id coming from
  two different providers is stored as two independent events. Every event is a
  map with `:provider`, `:event_id`, `:payload` and `:status` (always `:pending`).

  Intended for tests, single-node deployments and development; state is lost when
  the process stops.
  """

  use GenServer

  @behaviour WebhookReceiver.Store

  alias WebhookReceiver.Store

  @doc """
  Starts the in-memory store.

  Accepts the usual `GenServer` options, such as `:name`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {gen_opts, _rest} = Keyword.split(opts, [:name, :timeout, :debug, :spawn_opt, :hibernate_after])
    GenServer.start_link(__MODULE__, :ok, gen_opts)
  end

  @doc """
  Stores `payload` under `{provider, event_id}` with status `:pending`.

  See `WebhookReceiver.Store.store_event/4`.
  """
  @impl WebhookReceiver.Store
  @spec store_event(Store.store(), Store.provider(), Store.event_id(), map()) ::
          {:ok, :created} | {:ok, :duplicate}
  def store_event(store, provider, event_id, payload) do
    Store.store_event(store, provider, event_id, payload)
  end

  @doc """
  Fetches the event stored for `{provider, event_id}`.

  See `WebhookReceiver.Store.get_event/3`.
  """
  @impl WebhookReceiver.Store
  @spec get_event(Store.store(), Store.provider(), Store.event_id()) ::
          {:ok, Store.event()} | :error
  def get_event(store, provider, event_id) do
    Store.get_event(store, provider, event_id)
  end

  @doc """
  Returns every stored event as a list.

  See `WebhookReceiver.Store.all_events/1`.
  """
  @impl WebhookReceiver.Store
  @spec all_events(Store.store()) :: [Store.event()]
  def all_events(store) do
    Store.all_events(store)
  end

  @impl GenServer
  def init(:ok), do: {:ok, %{}}

  @impl GenServer
  def handle_call({:store_event, provider, event_id, payload}, _from, events) do
    key = {provider, event_id}

    case Map.fetch(events, key) do
      {:ok, _existing} ->
        {:reply, {:ok, :duplicate}, events}

      :error ->
        event = %{
          provider: provider,
          event_id: event_id,
          payload: payload,
          status: :pending
        }

        {:reply, {:ok, :created}, Map.put(events, key, event)}
    end
  end

  def handle_call({:get_event, provider, event_id}, _from, events) do
    {:reply, Map.fetch(events, {provider, event_id}), events}
  end

  def handle_call(:all_events, _from, events) do
    {:reply, Map.values(events), events}
  end
end

defmodule WebhookReceiver.Router do
  @moduledoc """
  `Plug.Router` exposing a multi-provider webhook endpoint at
  `POST /api/webhooks/:provider`.

  ## Options

    * `:providers` — map of provider name (string) to a config map:
      `%{secrets: [binary(), ...], header: header_name, prefix: prefix}`. `secrets`
      is ordered: the first entry is the current secret, later entries are being
      rotated out but are still accepted. `:prefix` is optional and defaults to
      `""`.
    * `:store` — the store process (required); see `WebhookReceiver.Store`.

  ## Responses

    * unknown provider → `404 {"error": "unknown_provider"}`
    * missing/empty signature header, or no secret matches →
      `401 {"error": "invalid_signature"}`
    * malformed JSON body or missing `"id"` → `400 {"error": "bad_payload"}`
    * new event → `200 {"status": "received"}`
    * event already stored for this provider → `200 {"status": "duplicate"}`

  Bodies are read raw so the signature is verified against the exact bytes sent by
  the provider, and only decoded afterwards.

  ## Example

      plug WebhookReceiver.Router,
        store: MyApp.WebhookStore,
        providers: %{
          "stripe" => %{
            secrets: ["current", "previous"],
            header: "stripe-signature"
          },
          "github" => %{
            secrets: ["gh-secret"],
            header: "x-hub-signature-256",
            prefix: "sha256="
          }
        }
  """

  use Plug.Router

  alias WebhookReceiver.Signature
  alias WebhookReceiver.Store

  plug :match
  plug :dispatch

  @doc """
  Builds the plug options, validating that `:store` and `:providers` are present.
  """
  @spec init(keyword()) :: map()
  def init(opts) do
    providers = Keyword.get(opts, :providers, %{})
    store = Keyword.fetch!(opts, :store)

    %{providers: providers, store: store}
  end

  @doc """
  Entry point invoked by `Plug`; dispatches the request through the router.
  """
  @spec call(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def call(conn, opts) do
    conn
    |> put_private(:webhook_receiver, opts)
    |> super(opts)
  end

  post "/api/webhooks/:provider" do
    %{providers: providers, store: store} = conn.private.webhook_receiver

    case Map.fetch(providers, provider) do
      {:ok, config} -> handle_webhook(conn, provider, config, store)
      :error -> send_json(conn, 404, %{"error" => "unknown_provider"})
    end
  end

  match _ do
    send_json(conn, 404, %{"error" => "not_found"})
  end

  @spec handle_webhook(Plug.Conn.t(), Store.provider(), map(), Store.store()) :: Plug.Conn.t()
  defp handle_webhook(conn, provider, config, store) do
    {:ok, body, conn} = read_raw_body(conn)

    with :ok <- verify_signature(conn, body, config),
         {:ok, payload, event_id} <- decode_payload(body) do
      case Store.store_event(store, provider, event_id, payload) do
        {:ok, :duplicate} -> send_json(conn, 200, %{"status" => "duplicate"})
        {:ok, :created} -> send_json(conn, 200, %{"status" => "received"})
      end
    else
      :invalid_signature -> send_json(conn, 401, %{"error" => "invalid_signature"})
      :bad_payload -> send_json(conn, 400, %{"error" => "bad_payload"})
    end
  end

  @spec verify_signature(Plug.Conn.t(), binary(), map()) :: :ok | :invalid_signature
  defp verify_signature(conn, body, config) do
    secrets = List.wrap(Map.get(config, :secrets, []))
    prefix = Map.get(config, :prefix) || ""
    header = config |> Map.get(:header, "") |> to_string() |> String.downcase()

    case signature_header(conn, header) do
      {:ok, signature} ->
        case Signature.verify_any(body, signature, secrets, prefix) do
          :ok -> :ok
          :error -> :invalid_signature
        end

      :error ->
        :invalid_signature
    end
  end

  @spec signature_header(Plug.Conn.t(), binary()) :: {:ok, binary()} | :error
  defp signature_header(_conn, ""), do: :error

  defp signature_header(conn, header) do
    case get_req_header(conn, header) do
      [value | _rest] when is_binary(value) and value != "" -> {:ok, value}
      _other -> :error
    end
  end

  @spec decode_payload(binary()) :: {:ok, map(), Store.event_id()} | :bad_payload
  defp decode_payload(body) do
    case Jason.decode(body) do
      {:ok, %{"id" => event_id} = payload} when is_binary(event_id) and event_id != "" ->
        {:ok, payload, event_id}

      {:ok, %{"id" => event_id} = payload} when is_integer(event_id) ->
        {:ok, payload, Integer.to_string(event_id)}

      _other ->
        :bad_payload
    end
  end

  @spec read_raw_body(Plug.Conn.t()) :: {:ok, binary(), Plug.Conn.t()}
  defp read_raw_body(conn) do
    read_raw_body(conn, [])
  end

  @spec read_raw_body(Plug.Conn.t(), [binary()]) :: {:ok, binary(), Plug.Conn.t()}
  defp read_raw_body(conn, chunks) do
    case Plug.Conn.read_body(conn) do
      {:ok, chunk, conn} ->
        {:ok, IO.iodata_to_binary(Enum.reverse([chunk | chunks])), conn}

      {:more, chunk, conn} ->
        read_raw_body(conn, [chunk | chunks])

      {:error, _reason} ->
        {:ok, IO.iodata_to_binary(Enum.reverse(chunks)), conn}
    end
  end

  @spec send_json(Plug.Conn.t(), non_neg_integer(), map()) :: Plug.Conn.t()
  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end