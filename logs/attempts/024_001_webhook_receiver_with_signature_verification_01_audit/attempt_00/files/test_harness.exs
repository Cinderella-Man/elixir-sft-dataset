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
    assert :error = WebhookReceiver.Signature.verify("hello", "not_hex_at_all!", @secret)
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

  test "malformed JSON with a bad signature is rejected 401 before any decoding", %{opts: opts} do
    bad_json = "this is not json {{"
    sig = sign(bad_json, "wrong_secret")

    conn = post_webhook(opts, bad_json, [{"stripe-signature", sig}])

    assert conn.status == 401
    assert json_body(conn)["error"] == "invalid_signature"
  end

  test "a 401-rejected delivery persists nothing, later valid delivery is received", ctx do
    %{opts: opts, store: store} = ctx
    payload = build_event("evt_reject_01")

    conn1 = post_webhook(opts, payload, [{"stripe-signature", sign(payload, "wrong_secret")}])
    assert conn1.status == 401
    assert :error = WebhookReceiver.Store.get_event(store, "evt_reject_01")

    conn2 = post_webhook(opts, payload, [{"stripe-signature", sign(payload, @secret)}])
    assert conn2.status == 200
    assert json_body(conn2)["status"] == "received"
  end

  test "router verifies against the :secret option value rather than a fixed key", %{store: store} do
    other_secret = "whsec_alternate_key_0987654321"
    opts = [secret: other_secret, store: store]

    payload = build_event("evt_secret_opt_1")
    conn = post_webhook(opts, payload, [{"stripe-signature", sign(payload, other_secret)}])
    assert conn.status == 200
    assert json_body(conn)["status"] == "received"

    payload2 = build_event("evt_secret_opt_2")
    conn2 = post_webhook(opts, payload2, [{"stripe-signature", sign(payload2, @secret)}])
    assert conn2.status == 401
    assert json_body(conn2)["error"] == "invalid_signature"
  end

  test "event lands in the store pid carried in opts and not in another store", %{store: store} do
    {:ok, other_store} = WebhookReceiver.MemoryStore.start_link([])
    payload = build_event("evt_pid_routed")
    sig = sign(payload, @secret)

    conn =
      post_webhook([secret: @secret, store: other_store], payload, [{"stripe-signature", sig}])

    assert conn.status == 200
    assert json_body(conn)["status"] == "received"

    assert {:ok, event} = WebhookReceiver.Store.get_event(other_store, "evt_pid_routed")
    assert event.event_id == "evt_pid_routed"
    assert :error = WebhookReceiver.Store.get_event(store, "evt_pid_routed")
  end

  test "payload whose id field is a JSON number is accepted rather than rejected", %{opts: opts} do
    payload = Jason.encode!(%{"id" => 12_345, "type" => "charge.completed", "data" => %{}})
    sig = sign(payload, @secret)

    conn = post_webhook(opts, payload, [{"stripe-signature", sig}])

    assert conn.status == 200
    assert json_body(conn)["status"] == "received"
  end

  test "all_events returns an empty list for a freshly started store", %{store: store} do
    assert WebhookReceiver.Store.all_events(store) == []
  end
end
