# Write tests for this module

Below is a completed Elixir module and the original specification it was built to
satisfy. Write a comprehensive ExUnit test harness that verifies a correct
implementation of this module.

Requirements for the harness:
- Define a module `<Module>Test` that does `use ExUnit.Case, async: false`.
- Do NOT call `ExUnit.start()` — the evaluator starts ExUnit itself.
- Make it self-contained: any fakes, clock Agents, or helpers are defined inline.
- Cover the full public API and the important edge cases described in the spec.
- It must compile with ZERO warnings (prefix unused variables with `_`; match float
  zero as `+0.0`/`-0.0`).
- Give me the complete harness in a single file.

## Original specification

Write me an Elixir module called `WebhookReceiver` that implements a Plug-based **multi-provider** webhook endpoint with HMAC-SHA256 signature verification and support for **secret rotation** (multiple simultaneously-valid keys per provider).

I need these modules:

1. `WebhookReceiver.Signature` — a module with:
   - `verify(payload, signature, secret, prefix \\ "")` — compute the lowercase hex HMAC-SHA256 of `payload` with `secret`, prepend `prefix` (e.g. `"sha256="`), and constant-time compare against `signature`. Return `:ok` or `:error`. Non-binary inputs return `:error`.
   - `verify_any(payload, signature, secrets, prefix \\ "")` — return `:ok` if `verify/4` succeeds for ANY secret in the `secrets` list, else `:error`.

2. `WebhookReceiver.Store` — a behaviour with callbacks:
   - `store_event(store, provider, event_id, payload)` — persist keyed by `{provider, event_id}` with status `:pending`; `{:ok, :duplicate}` if that provider/id pair exists, `{:ok, :created}` otherwise.
   - `get_event(store, provider, event_id)` — `{:ok, event}` or `:error`.
   - `all_events(store)` — all stored events as a list.

3. `WebhookReceiver.MemoryStore` — a GenServer implementing the behaviour. Each event is a map with at least `:provider`, `:event_id`, `:payload`, and `:status` (`:pending`).

4. `WebhookReceiver.Router` — a `Plug.Router` exposing `POST /api/webhooks/:provider`. Options:
   - `:providers` — a map from provider name (string) to a config map `%{secrets: [binary, ...], header: header_name, prefix: prefix}` where `prefix` is optional (default `""`). `secrets` is a list; the FIRST is current, later ones are being rotated out but still accepted.
   - `:store` — the store process (required).

Router behaviour:
- Look up `provider` from the path. If it isn't in `:providers`, return **404** `{"error": "unknown_provider"}`.
- Read the raw body once and the provider's configured signature header.
- Missing/empty header or no secret matches → **401** `{"error": "invalid_signature"}`.
- On success decode the JSON, extract `"id"`:
  - already stored for this provider → **200** `{"status": "duplicate"}`
  - new → store and **200** `{"status": "received"}`
- Malformed JSON or missing `"id"` → **400** `{"error": "bad_payload"}`.

Two different providers may share the same event id without colliding. Use only Plug and Jason (plus `:crypto`). No Phoenix, no Ecto. Give me all modules in a single file.

## Additional interface contract

- `WebhookReceiver.Store` is not just a behaviour definition: it must ALSO define public client functions with the same names and arities as its callbacks, each dispatching to the given store process (e.g. via `GenServer.call(store, ...)`), so callers can invoke e.g. `WebhookReceiver.Store.get_event(store, provider, event_id)` directly on the module.

## Module under test

```elixir
defmodule WebhookReceiver.Signature do
  @moduledoc """
  HMAC-SHA256 verification supporting an optional prefix and multiple valid
  secrets (key rotation).
  """

  @doc """
  Verify `signature` against the lowercase hex HMAC-SHA256 of `payload` keyed
  by `secret`, with an optional `prefix` (e.g. `"sha256="`). The comparison is
  constant-time. Returns `:ok` on a match, `:error` otherwise (including for
  any non-binary input).
  """
  @spec verify(term(), term(), term(), term()) :: :ok | :error
  def verify(payload, signature, secret, prefix \\ "")

  def verify(payload, signature, secret, prefix)
      when is_binary(payload) and is_binary(signature) and
             is_binary(secret) and is_binary(prefix) do
    expected = prefix <> lower_hex_hmac(secret, payload)

    if Plug.Crypto.secure_compare(expected, signature) do
      :ok
    else
      :error
    end
  end

  def verify(_payload, _signature, _secret, _prefix), do: :error

  @doc """
  Return `:ok` if `verify/4` succeeds for ANY secret in the `secrets` list,
  otherwise `:error`. Useful for accepting a rotatable set of secrets.
  """
  @spec verify_any(term(), term(), [binary()], binary()) :: :ok | :error
  def verify_any(payload, signature, secrets, prefix \\ "") when is_list(secrets) do
    if Enum.any?(secrets, fn s -> verify(payload, signature, s, prefix) == :ok end) do
      :ok
    else
      :error
    end
  end

  defp lower_hex_hmac(secret, payload) do
    :crypto.mac(:hmac, :sha256, secret, payload) |> Base.encode16(case: :lower)
  end
end

defmodule WebhookReceiver.Store do
  @moduledoc """
  Behaviour describing a provider-namespaced webhook event store.
  """

  @callback store_event(
              store :: pid() | atom(),
              provider :: String.t(),
              event_id :: String.t(),
              payload :: map()
            ) :: {:ok, :created | :duplicate}
  @callback get_event(store :: pid() | atom(), provider :: String.t(), event_id :: String.t()) ::
              {:ok, map()} | :error
  @callback all_events(store :: pid() | atom()) :: [map()]

  @doc """
  Persist an event keyed by `{provider, event_id}` with status `:pending`.
  Returns `{:ok, :duplicate}` if the pair exists, `{:ok, :created}` otherwise.
  """
  @spec store_event(pid() | atom(), String.t(), String.t(), map()) ::
          {:ok, :created | :duplicate}
  def store_event(store, provider, event_id, payload) do
    GenServer.call(store, {:store_event, provider, event_id, payload})
  end

  @doc """
  Fetch a previously stored event, returning `{:ok, event}` or `:error`.
  """
  @spec get_event(pid() | atom(), String.t(), String.t()) :: {:ok, map()} | :error
  def get_event(store, provider, event_id) do
    GenServer.call(store, {:get_event, provider, event_id})
  end

  @doc """
  Return all stored events as a list.
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
  Start the in-memory store. Accepts standard `GenServer` options such as
  `:name`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @doc """
  Persist an event; see `WebhookReceiver.Store.store_event/4`.
  """
  @spec store_event(pid() | atom(), String.t(), String.t(), map()) ::
          {:ok, :created | :duplicate}
  @impl WebhookReceiver.Store
  def store_event(store, provider, event_id, payload) do
    GenServer.call(store, {:store_event, provider, event_id, payload})
  end

  @doc """
  Fetch an event; see `WebhookReceiver.Store.get_event/3`.
  """
  @spec get_event(pid() | atom(), String.t(), String.t()) :: {:ok, map()} | :error
  @impl WebhookReceiver.Store
  def get_event(store, provider, event_id) do
    GenServer.call(store, {:get_event, provider, event_id})
  end

  @doc """
  Return all events; see `WebhookReceiver.Store.all_events/1`.
  """
  @spec all_events(pid() | atom()) :: [map()]
  @impl WebhookReceiver.Store
  def all_events(store) do
    GenServer.call(store, :all_events)
  end

  @doc """
  Initialize the store with an empty event map.
  """
  @spec init(keyword()) :: {:ok, %{events: map()}}
  @impl GenServer
  def init(_opts), do: {:ok, %{events: %{}}}

  @doc """
  Handle synchronous store calls (`:store_event`, `:get_event`, `:all_events`).
  """
  @spec handle_call(term(), GenServer.from(), %{events: map()}) ::
          {:reply, term(), %{events: map()}}
  @impl GenServer
  def handle_call(
        {:store_event, provider, event_id, payload},
        _from,
        %{events: events} = state
      ) do
    key = {provider, event_id}

    if Map.has_key?(events, key) do
      {:reply, {:ok, :duplicate}, state}
    else
      event = %{provider: provider, event_id: event_id, payload: payload, status: :pending}
      {:reply, {:ok, :created}, %{state | events: Map.put(events, key, event)}}
    end
  end

  @impl GenServer
  def handle_call({:get_event, provider, event_id}, _from, %{events: events} = state) do
    case Map.fetch(events, {provider, event_id}) do
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
  `Plug.Router` receiving webhooks for multiple providers at
  `POST /api/webhooks/:provider`, each with its own header/prefix and a
  rotatable list of secrets.
  """

  use Plug.Router, copy_opts_to_assign: :webhook_opts

  alias WebhookReceiver.{Signature, Store}

  plug(:match)
  plug(:dispatch)

  post "/api/webhooks/:provider" do
    opts = conn.assigns.webhook_opts
    providers = Keyword.fetch!(opts, :providers)
    store = Keyword.fetch!(opts, :store)

    case Map.fetch(providers, provider) do
      :error ->
        send_json(conn, 404, %{error: "unknown_provider"})

      {:ok, config} ->
        handle_provider(conn, provider, config, store)
    end
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

  defp handle_provider(conn, provider, config, store) do
    header_name = Map.fetch!(config, :header)
    secrets = Map.fetch!(config, :secrets)
    prefix = Map.get(config, :prefix, "")

    {:ok, body, conn} = read_body(conn)
    signature = conn |> get_req_header(header_name) |> List.first()

    cond do
      is_nil(signature) or signature == "" ->
        send_json(conn, 401, %{error: "invalid_signature"})

      Signature.verify_any(body, signature, secrets, prefix) != :ok ->
        send_json(conn, 401, %{error: "invalid_signature"})

      true ->
        handle_verified(conn, provider, body, store)
    end
  end

  defp handle_verified(conn, provider, body, store) do
    case Jason.decode(body) do
      {:ok, %{"id" => event_id} = payload} when is_binary(event_id) ->
        case Store.store_event(store, provider, event_id, payload) do
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
