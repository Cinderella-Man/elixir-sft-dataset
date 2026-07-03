Implement the private `handle_verified/3` function. It is called with the `conn`,
the raw request `body` (a string whose signature has already been verified), and
the `store` module after a successful signature check. It must decode the raw body
as JSON using `Jason.decode/1` and act on the result:

- If decoding succeeds and the decoded value is a map containing a binary `"id"`
  field, treat that value as the `event_id`, keep the whole decoded map as the
  payload, and persist it via `WebhookReceiver.Store.store_event/3`. When the store
  returns `{:ok, :created}`, respond 200 with the JSON body `%{status: "received"}`;
  when it returns `{:ok, :duplicate}`, respond 200 with `%{status: "duplicate"}`.
- If decoding succeeds but the value is not a map with a binary `"id"` field,
  respond 400 with `%{error: "bad_payload"}`.
- If decoding fails, respond 400 with `%{error: "bad_payload"}`.

Use the existing `send_json/3` helper to build every response.

```elixir
defmodule WebhookReceiver.Signature do
  @moduledoc """
  HMAC-SHA256 signature verification for webhook payloads.
  """

  @doc """
  Computes HMAC-SHA256 of `payload` with `secret` and compares it, in
  constant time, against the hex-encoded `signature`. Returns `:ok` or `:error`.
  """
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
    # TODO
  end

  defp send_json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
```