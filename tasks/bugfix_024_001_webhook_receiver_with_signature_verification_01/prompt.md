# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

Write me an Elixir module called `WebhookReceiver` that implements a Plug-based HTTP endpoint for receiving webhook payloads with HMAC-SHA256 signature verification.

I need these modules:

1. `WebhookReceiver.Router` — a `Plug.Router` that exposes `POST /api/webhooks/stripe`. It should accept a `:secret` option (the HMAC signing key) and a `:store` option (a module implementing the storage behaviour). Parse the raw body, verify the signature from the `stripe-signature` header, and delegate to the store.

2. `WebhookReceiver.Signature` — a module with a single public function `verify(payload, signature, secret)` that computes HMAC-SHA256 of the raw payload string using the secret, and compares it (in constant-time) to the hex-encoded signature provided. Return `:ok` or `:error`. The hex encoding is lower-case. A signature that is not valid hex (garbage input) must return `:error`, not raise.

3. `WebhookReceiver.Store` — a behaviour with two callbacks:
   - `store_event(store_pid, event_id, payload)` — persist the event with status `:pending`. If the event_id already exists, return `{:ok, :duplicate}` and leave the already-stored event unchanged (do not overwrite its payload). If it's new, return `{:ok, :created}`.
   - `get_event(store_pid, event_id)` — return `{:ok, event}` or `:error`.
   - `all_events(store_pid)` — return all stored events as a list.

4. `WebhookReceiver.MemoryStore` — a GenServer implementing the `WebhookReceiver.Store` behaviour using an in-memory map. It should expose `start_link/1` (accepting an options list). Each stored event should be a map with at least `:event_id`, `:payload` (the decoded map, with string keys), and `:status` (always `:pending` on creation).

The router should behave as follows:
- Read the raw request body and the `stripe-signature` header.
- If the signature header is missing, empty, or verification fails, return 401 with a JSON body `{"error": "invalid_signature"}`.
- If verification passes, decode the JSON body, extract the `"id"` field as the event ID.
- If the event ID has already been stored, return 200 with `{"status": "duplicate"}`.
- If new, store it and return 200 with `{"status": "received"}`.
- If the JSON body is malformed or missing an `"id"` field, return 400 with `{"error": "bad_payload"}`.
- Any request that does not match `POST /api/webhooks/stripe` (a different path, or a different method on that path) should return 404 with a plain-text body.

The raw body must be read and kept available for both signature verification and JSON decoding. Use a custom body reader or cache the raw body in the conn's assigns.

Use only Plug and Jason as dependencies (plus :crypto from OTP). No Phoenix, no Ecto, no database drivers. Give me all modules in a single file.

## Additional interface contract

- The `:store` option's value is the **pid** of an already-started store
  process, not a module name: callers do
  `{:ok, store} = WebhookReceiver.MemoryStore.start_link([])` and then invoke
  the router directly via
  `WebhookReceiver.Router.init(secret: secret, store: store)` followed by
  `WebhookReceiver.Router.call(conn, init_result)`. `init/1` must therefore
  carry the options through to `call/2` (e.g.
  `use Plug.Router, copy_opts_to_assign: :webhook_opts`), and the router
  passes that pid as the first argument of every `WebhookReceiver.Store` call.

- `WebhookReceiver.Store` is not just a behaviour definition: it must ALSO define public client functions with the same names and arities as its callbacks, each dispatching to the given store process (e.g. via `GenServer.call(store, ...)`), so callers can invoke e.g. `WebhookReceiver.Store.get_event(store, event_id)` directly on the module.

## The buggy module

```elixir
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

      false ->
        handle_verified(conn, body, store)
    end
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

  defp handle_verified(conn, body, store) do
    case Jason.decode(body) do
      {:ok, %{"id" => event_id} = payload} when is_binary(event_id) ->
        case Store.store_event(store, event_id, payload) do
          {:ok, :created} -> send_json(conn, 200, %{status: "received"})
          {:ok, :duplicate} -> send_json(conn, 200, %{status: "duplicate"})
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

## Failing test report

```
6 of 18 test(s) failed:

  * test returns 200 and stores event when signature is valid
      ** (CondClauseError) no cond clause evaluated to a truthy value

  * test duplicate event ID returns 200 with duplicate status
      ** (CondClauseError) no cond clause evaluated to a truthy value

  * test duplicate is detected even with different payload bodies sharing the same id
      ** (CondClauseError) no cond clause evaluated to a truthy value

  * test returns 400 when JSON is malformed
      ** (CondClauseError) no cond clause evaluated to a truthy value

  (…2 more)
```
