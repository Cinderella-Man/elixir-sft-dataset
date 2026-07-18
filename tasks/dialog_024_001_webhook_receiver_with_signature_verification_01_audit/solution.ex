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

  @doc """
  Persists `payload` under `event_id` in the store process `store`.

  Returns `{:ok, :created}` for a new event and `{:ok, :duplicate}` when the
  event id has already been stored.
  """
  @spec store_event(pid() | atom(), String.t(), map()) :: {:ok, :created | :duplicate}
  def store_event(store, event_id, payload) do
    GenServer.call(store, {:store_event, event_id, payload})
  end

  @doc """
  Fetches the event stored under `event_id`, returning `{:ok, event}` or `:error`.
  """
  @spec get_event(pid() | atom(), String.t()) :: {:ok, map()} | :error
  def get_event(store, event_id) do
    GenServer.call(store, {:get_event, event_id})
  end

  @doc """
  Returns every event currently held by the store process `store`.
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
  Starts the in-memory store. Accepts the standard `:name` option.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @doc """
  Persists `payload` under `event_id` with status `:pending`.
  """
  @impl WebhookReceiver.Store
  @spec store_event(pid() | atom(), String.t(), map()) :: {:ok, :created | :duplicate}
  def store_event(store, event_id, payload) do
    GenServer.call(store, {:store_event, event_id, payload})
  end

  @doc """
  Fetches the event stored under `event_id`.
  """
  @impl WebhookReceiver.Store
  @spec get_event(pid() | atom(), String.t()) :: {:ok, map()} | :error
  def get_event(store, event_id) do
    GenServer.call(store, {:get_event, event_id})
  end

  @doc """
  Returns every stored event.
  """
  @impl WebhookReceiver.Store
  @spec all_events(pid() | atom()) :: [map()]
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
      {:ok, %{"id" => raw_id} = payload} ->
        case normalize_id(raw_id) do
          {:ok, event_id} -> store_and_reply(conn, store, event_id, payload)
          :error -> send_json(conn, 400, %{error: "bad_payload"})
        end

      {:ok, _decoded} ->
        send_json(conn, 400, %{error: "bad_payload"})

      {:error, _reason} ->
        send_json(conn, 400, %{error: "bad_payload"})
    end
  end

  defp store_and_reply(conn, store, event_id, payload) do
    case Store.store_event(store, event_id, payload) do
      {:ok, :created} -> send_json(conn, 200, %{status: "received"})
      {:ok, :duplicate} -> send_json(conn, 200, %{status: "duplicate"})
    end
  end

  # Stripe-style ids are strings, but a JSON number (or boolean) is still an
  # unambiguous scalar identifier, so coerce it to its string form.
  defp normalize_id(id) when is_binary(id) and id != "", do: {:ok, id}
  defp normalize_id(id) when is_integer(id), do: {:ok, Integer.to_string(id)}
  defp normalize_id(id) when is_float(id), do: {:ok, Float.to_string(id)}
  defp normalize_id(id) when is_boolean(id), do: {:ok, to_string(id)}
  defp normalize_id(_id), do: :error

  defp send_json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
