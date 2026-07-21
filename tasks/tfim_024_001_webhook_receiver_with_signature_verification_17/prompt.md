# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

      true ->
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

## Test harness — implement the `# TODO` test

```elixir
defmodule WebhookReceiverTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  # --- Helpers -----------------------------------------------------------

  @secret "whsec_test_secret_key_1234567890"

  defp sign(payload, secret) do
    :crypto.mac(:hmac, :sha256, secret, payload)
    |> Base.encode16(case: :lower)
  end

  defp build_event(id, type \\ "charge.completed") do
    Jason.encode!(%{
      "id" => id,
      "type" => type,
      "data" => %{"amount" => 2500, "currency" => "usd"}
    })
  end

  defp json_body(conn) do
    Jason.decode!(conn.resp_body)
  end

  setup do
    {:ok, store} = WebhookReceiver.MemoryStore.start_link([])

    router_opts = [secret: @secret, store: store]

    # Build a small wrapper so we can pass opts through to the router.
    # Plug.Test calls init/1 then call/2, so we create a thin anonymous
    # module-like helper that captures the opts.
    defmodule :"TestRouter_#{System.unique_integer([:positive])}" do
    end

    %{store: store, opts: router_opts}
  end

  # We need a way to call the router with our opts.  We'll define a
  # helper that manually invokes the plug pipeline.
  defp do_request(opts, method, path, payload, headers \\ []) do
    conn = conn(method, path, payload)

    conn =
      Enum.reduce(headers, conn, fn {k, v}, acc ->
        put_req_header(acc, k, v)
      end)

    conn = put_req_header(conn, "content-type", "application/json")

    # init returns the opts the router needs; call dispatches
    router_init = WebhookReceiver.Router.init(opts)
    WebhookReceiver.Router.call(conn, router_init)
  end

  defp post_webhook(opts, payload, headers) do
    do_request(opts, :post, "/api/webhooks/stripe", payload, headers)
  end

  # -------------------------------------------------------
  # Signature verification — valid
  # -------------------------------------------------------

  test "returns 200 and stores event when signature is valid", %{opts: opts, store: store} do
    payload = build_event("evt_001")
    sig = sign(payload, @secret)

    conn = post_webhook(opts, payload, [{"stripe-signature", sig}])

    assert conn.status == 200
    assert json_body(conn)["status"] == "received"

    # Verify the event was persisted
    assert {:ok, event} = WebhookReceiver.Store.get_event(store, "evt_001")
    assert event.event_id == "evt_001"
    assert event.status == :pending
    assert event.payload["type"] == "charge.completed"
  end

  # -------------------------------------------------------
  # Signature verification — invalid
  # -------------------------------------------------------

  test "returns 401 when signature is wrong", %{opts: opts} do
    payload = build_event("evt_002")
    bad_sig = sign(payload, "wrong_secret")

    conn = post_webhook(opts, payload, [{"stripe-signature", bad_sig}])

    assert conn.status == 401
    assert json_body(conn)["error"] == "invalid_signature"
  end

  test "returns 401 when signature header is missing", %{opts: opts} do
    payload = build_event("evt_003")

    conn = post_webhook(opts, payload, [])

    assert conn.status == 401
    assert json_body(conn)["error"] == "invalid_signature"
  end

  test "returns 401 when signature is empty string", %{opts: opts} do
    payload = build_event("evt_004")

    conn = post_webhook(opts, payload, [{"stripe-signature", ""}])

    assert conn.status == 401
    assert json_body(conn)["error"] == "invalid_signature"
  end

  test "returns 401 when payload has been tampered with", %{opts: opts} do
    original = build_event("evt_005")
    sig = sign(original, @secret)

    tampered =
      Jason.encode!(%{
        "id" => "evt_005",
        "type" => "charge.completed",
        "data" => %{"amount" => 999_999, "currency" => "usd"}
      })

    conn = post_webhook(opts, tampered, [{"stripe-signature", sig}])

    assert conn.status == 401
    assert json_body(conn)["error"] == "invalid_signature"
  end

  # -------------------------------------------------------
  # Duplicate handling
  # -------------------------------------------------------

  test "duplicate event ID returns 200 with duplicate status", %{opts: opts, store: store} do
    payload = build_event("evt_010")
    sig = sign(payload, @secret)

    conn1 = post_webhook(opts, payload, [{"stripe-signature", sig}])
    assert conn1.status == 200
    assert json_body(conn1)["status"] == "received"

    conn2 = post_webhook(opts, payload, [{"stripe-signature", sig}])
    assert conn2.status == 200
    assert json_body(conn2)["status"] == "duplicate"

    # Only one record in the store
    events = WebhookReceiver.Store.all_events(store)
    matching = Enum.filter(events, &(&1.event_id == "evt_010"))
    assert length(matching) == 1
  end

  test "duplicate is detected even with different payload bodies sharing the same id", %{
    opts: opts,
    store: store
  } do
    payload1 = build_event("evt_011", "charge.completed")
    sig1 = sign(payload1, @secret)

    conn1 = post_webhook(opts, payload1, [{"stripe-signature", sig1}])
    assert conn1.status == 200
    assert json_body(conn1)["status"] == "received"

    # Second delivery with same id but different type
    payload2 = build_event("evt_011", "charge.updated")
    sig2 = sign(payload2, @secret)

    conn2 = post_webhook(opts, payload2, [{"stripe-signature", sig2}])
    assert conn2.status == 200
    assert json_body(conn2)["status"] == "duplicate"

    # Original payload is preserved, not overwritten
    {:ok, event} = WebhookReceiver.Store.get_event(store, "evt_011")
    assert event.payload["type"] == "charge.completed"
  end

  # -------------------------------------------------------
  # Bad payloads
  # -------------------------------------------------------

  test "returns 400 when JSON is malformed", %{opts: opts} do
    bad_json = "this is not json {{"
    sig = sign(bad_json, @secret)

    conn = post_webhook(opts, bad_json, [{"stripe-signature", sig}])

    assert conn.status == 400
    assert json_body(conn)["error"] == "bad_payload"
  end

  test "returns 400 when payload is valid JSON but missing id field", %{opts: opts} do
    payload = Jason.encode!(%{"type" => "charge.completed", "data" => %{}})
    sig = sign(payload, @secret)

    conn = post_webhook(opts, payload, [{"stripe-signature", sig}])

    assert conn.status == 400
    assert json_body(conn)["error"] == "bad_payload"
  end

  # -------------------------------------------------------
  # Key independence — different event IDs
  # -------------------------------------------------------

  test "distinct event IDs are stored independently", %{opts: opts, store: store} do
    for i <- 1..5 do
      id = "evt_multi_#{i}"
      payload = build_event(id)
      sig = sign(payload, @secret)

      conn = post_webhook(opts, payload, [{"stripe-signature", sig}])
      assert conn.status == 200
      assert json_body(conn)["status"] == "received"
    end

    events = WebhookReceiver.Store.all_events(store)
    assert length(events) == 5
  end

  # -------------------------------------------------------
  # Store behaviour — direct unit tests
  # -------------------------------------------------------

  test "MemoryStore stores and retrieves events", %{store: store} do
    assert {:ok, :created} =
             WebhookReceiver.Store.store_event(store, "evt_100", %{"id" => "evt_100"})

    assert {:ok, event} = WebhookReceiver.Store.get_event(store, "evt_100")
    assert event.event_id == "evt_100"
    assert event.status == :pending
  end

  test "MemoryStore returns duplicate for repeated event_id", %{store: store} do
    assert {:ok, :created} =
             WebhookReceiver.Store.store_event(store, "evt_200", %{"id" => "evt_200"})

    assert {:ok, :duplicate} =
             WebhookReceiver.Store.store_event(store, "evt_200", %{"id" => "evt_200"})
  end

  test "MemoryStore returns :error for unknown event", %{store: store} do
    assert :error = WebhookReceiver.Store.get_event(store, "evt_nonexistent")
  end

  # -------------------------------------------------------
  # Signature module — direct unit tests
  # -------------------------------------------------------

  test "Signature.verify/3 returns :ok for correct signature" do
    payload = "hello"
    sig = sign(payload, @secret)
    assert :ok = WebhookReceiver.Signature.verify(payload, sig, @secret)
  end

  test "Signature.verify/3 returns :error for wrong signature" do
    payload = "hello"
    sig = sign(payload, "other_secret")
    assert :error = WebhookReceiver.Signature.verify(payload, sig, @secret)
  end

  test "Signature.verify/3 returns :error for garbage signature" do
    # TODO
  end

  # -------------------------------------------------------
  # Route miss
  # -------------------------------------------------------

  test "GET to the webhook path returns 404 or 405", %{opts: opts} do
    conn = do_request(opts, :get, "/api/webhooks/stripe", "")
    assert conn.status in [404, 405]
  end

  test "POST to an unknown path returns 404", %{opts: opts} do
    payload = build_event("evt_999")
    sig = sign(payload, @secret)

    conn = do_request(opts, :post, "/api/webhooks/unknown", payload, [{"stripe-signature", sig}])
    assert conn.status == 404
  end

  # A non-POST method on the webhook path is a route miss like any other:
  # the documented status is 404 exactly, never a method-specific 405.
  test "non-POST methods on the webhook path return exactly 404, not 405", %{opts: opts} do
    for method <- [:get, :put, :delete] do
      conn = do_request(opts, method, "/api/webhooks/stripe", "")
      assert conn.status == 404
    end
  end

  # Route misses answer with a plain-text body, so the body must not be a
  # JSON object and the response must not be advertised as JSON.
  test "route misses respond with a plain-text body rather than JSON", %{opts: opts} do
    conns = [
      do_request(opts, :get, "/api/webhooks/stripe", ""),
      do_request(opts, :post, "/api/webhooks/unrouted", build_event("evt_miss"))
    ]

    for conn <- conns do
      assert conn.status == 404
      assert is_binary(conn.resp_body)
      assert conn.resp_body != ""

      refute Enum.any?(get_resp_header(conn, "content-type"), fn value ->
               String.contains?(value, "json")
             end)

      refute match?({:ok, %{}}, Jason.decode(conn.resp_body))
    end
  end
end
```
