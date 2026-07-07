# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

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

  plug :match
  plug :dispatch

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

## Test harness — implement the `# TODO` test

```elixir
defmodule WebhookReceiverMultiProviderTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  @stripe "whsec_stripe_secret"
  @gh_new "gh_new_secret"
  @gh_old "gh_old_secret"

  defp hmac_hex(payload, secret) do
    :crypto.mac(:hmac, :sha256, secret, payload) |> Base.encode16(case: :lower)
  end

  defp stripe_sig(payload, secret), do: hmac_hex(payload, secret)
  defp gh_sig(payload, secret), do: "sha256=" <> hmac_hex(payload, secret)

  defp build_event(id, type \\ "charge.completed") do
    Jason.encode!(%{"id" => id, "type" => type, "data" => %{"amount" => 100}})
  end

  defp json_body(conn), do: Jason.decode!(conn.resp_body)

  setup do
    {:ok, store} = WebhookReceiver.MemoryStore.start_link([])

    providers = %{
      "stripe" => %{secrets: [@stripe], header: "stripe-signature", prefix: ""},
      "github" => %{secrets: [@gh_new, @gh_old], header: "x-hub-signature-256", prefix: "sha256="}
    }

    %{store: store, opts: [providers: providers, store: store]}
  end

  defp do_request(opts, method, path, payload, headers) do
    conn = conn(method, path, payload)

    conn =
      Enum.reduce(headers, conn, fn {k, v}, acc -> put_req_header(acc, k, v) end)

    conn = put_req_header(conn, "content-type", "application/json")
    WebhookReceiver.Router.call(conn, WebhookReceiver.Router.init(opts))
  end

  defp post_webhook(opts, provider, payload, headers) do
    do_request(opts, :post, "/api/webhooks/#{provider}", payload, headers)
  end

  test "stripe provider verifies and stores", %{opts: opts, store: store} do
    payload = build_event("evt_s1")
    conn = post_webhook(opts, "stripe", payload, [{"stripe-signature", stripe_sig(payload, @stripe)}])

    assert conn.status == 200
    assert json_body(conn)["status"] == "received"
    assert {:ok, event} = WebhookReceiver.Store.get_event(store, "stripe", "evt_s1")
    assert event.provider == "stripe"
    assert event.status == :pending
  end

  test "github provider verifies with prefix and current secret", %{opts: opts} do
    payload = build_event("evt_g1")
    conn =
      post_webhook(opts, "github", payload, [{"x-hub-signature-256", gh_sig(payload, @gh_new)}])

    assert conn.status == 200
    assert json_body(conn)["status"] == "received"
  end

  test "github accepts a rotated-out (old) secret", %{opts: opts} do
    payload = build_event("evt_g2")
    conn =
      post_webhook(opts, "github", payload, [{"x-hub-signature-256", gh_sig(payload, @gh_old)}])

    assert conn.status == 200
    assert json_body(conn)["status"] == "received"
  end

  test "github rejects an unknown secret", %{opts: opts} do
    payload = build_event("evt_g3")
    conn =
      post_webhook(opts, "github", payload, [{"x-hub-signature-256", gh_sig(payload, "rogue")}])

    assert conn.status == 401
    assert json_body(conn)["error"] == "invalid_signature"
  end

  test "stripe rejects wrong signature", %{opts: opts} do
    payload = build_event("evt_s2")
    conn =
      post_webhook(opts, "stripe", payload, [{"stripe-signature", stripe_sig(payload, "wrong")}])

    assert conn.status == 401
    assert json_body(conn)["error"] == "invalid_signature"
  end

  test "unknown provider returns 404 unknown_provider", %{opts: opts} do
    payload = build_event("evt_x")
    conn =
      post_webhook(opts, "paypal", payload, [{"stripe-signature", stripe_sig(payload, @stripe)}])

    assert conn.status == 404
    assert json_body(conn)["error"] == "unknown_provider"
  end

  test "missing header returns invalid_signature", %{opts: opts} do
    conn = post_webhook(opts, "stripe", build_event("evt_s3"), [])
    assert conn.status == 401
    assert json_body(conn)["error"] == "invalid_signature"
  end

  test "github signature sent to stripe (wrong header) is rejected", %{opts: opts} do
    payload = build_event("evt_s4")
    conn =
      post_webhook(opts, "stripe", payload, [{"x-hub-signature-256", gh_sig(payload, @stripe)}])

    assert conn.status == 401
  end

  test "same id under different providers stored independently", %{opts: opts, store: store} do
    # TODO
  end

  test "duplicate within provider returns duplicate", %{opts: opts, store: store} do
    payload = build_event("evt_dup")
    sig = stripe_sig(payload, @stripe)

    c1 = post_webhook(opts, "stripe", payload, [{"stripe-signature", sig}])
    c2 = post_webhook(opts, "stripe", payload, [{"stripe-signature", sig}])

    assert json_body(c1)["status"] == "received"
    assert json_body(c2)["status"] == "duplicate"

    events = WebhookReceiver.Store.all_events(store)
    assert length(Enum.filter(events, &(&1.event_id == "evt_dup"))) == 1
  end

  test "malformed JSON returns bad_payload", %{opts: opts} do
    bad = "nope {{"
    conn = post_webhook(opts, "stripe", bad, [{"stripe-signature", stripe_sig(bad, @stripe)}])
    assert conn.status == 400
    assert json_body(conn)["error"] == "bad_payload"
  end

  test "missing id returns bad_payload", %{opts: opts} do
    payload = Jason.encode!(%{"type" => "x"})
    conn =
      post_webhook(opts, "stripe", payload, [{"stripe-signature", stripe_sig(payload, @stripe)}])

    assert conn.status == 400
    assert json_body(conn)["error"] == "bad_payload"
  end

  test "Signature.verify_any/4 succeeds on any matching secret" do
    payload = "hello"
    hex = :crypto.mac(:hmac, :sha256, @gh_old, payload) |> Base.encode16(case: :lower)
    sig = "sha256=" <> hex
    assert :ok = WebhookReceiver.Signature.verify_any(payload, sig, [@gh_new, @gh_old], "sha256=")
    assert :error = WebhookReceiver.Signature.verify_any(payload, sig, [@gh_new], "sha256=")
  end

  test "Signature.verify/4 returns :error for non-binary input" do
    assert :error = WebhookReceiver.Signature.verify(nil, "x", "y")
  end

  test "POST to unknown path returns 404", %{opts: opts} do
    conn = do_request(opts, :post, "/api/other/stripe", build_event("evt_z"), [])
    assert conn.status == 404
  end
end
```
