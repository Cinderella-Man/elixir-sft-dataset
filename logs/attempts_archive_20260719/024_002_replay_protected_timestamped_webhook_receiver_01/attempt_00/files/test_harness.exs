defmodule WebhookReceiverReplayTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  @secret "whsec_test_secret_key_1234567890"
  @now 1_700_000_000

  defp v1(ts, payload, secret) do
    :crypto.mac(:hmac, :sha256, secret, "#{ts}.#{payload}")
    |> Base.encode16(case: :lower)
  end

  defp header(ts, payload, secret) do
    "t=#{ts},v1=#{v1(ts, payload, secret)}"
  end

  defp build_event(id, type \\ "charge.completed") do
    Jason.encode!(%{
      "id" => id,
      "type" => type,
      "data" => %{"amount" => 2500, "currency" => "usd"}
    })
  end

  defp json_body(conn), do: Jason.decode!(conn.resp_body)

  setup do
    {:ok, store} = WebhookReceiver.MemoryStore.start_link([])
    opts = [secret: @secret, store: store, now: @now, tolerance: 300]
    %{store: store, opts: opts}
  end

  defp do_request(opts, method, path, payload, headers \\ []) do
    conn = conn(method, path, payload)

    conn =
      Enum.reduce(headers, conn, fn {k, v}, acc -> put_req_header(acc, k, v) end)

    conn = put_req_header(conn, "content-type", "application/json")
    WebhookReceiver.Router.call(conn, WebhookReceiver.Router.init(opts))
  end

  defp post_webhook(opts, payload, headers) do
    do_request(opts, :post, "/api/webhooks/stripe", payload, headers)
  end

  test "valid, in-window signature stores event", %{opts: opts, store: store} do
    payload = build_event("evt_001")
    conn = post_webhook(opts, payload, [{"stripe-signature", header(@now, payload, @secret)}])

    assert conn.status == 200
    assert json_body(conn)["status"] == "received"
    assert {:ok, event} = WebhookReceiver.Store.get_event(store, "evt_001")
    assert event.event_id == "evt_001"
    assert event.status == :pending
    assert event.payload["type"] == "charge.completed"
  end

  test "signature just inside the tolerance window is accepted", %{opts: opts} do
    payload = build_event("evt_edge")
    ts = @now - 300
    conn = post_webhook(opts, payload, [{"stripe-signature", header(ts, payload, @secret)}])
    assert conn.status == 200
    assert json_body(conn)["status"] == "received"
  end

  test "expired (too old) timestamp returns timestamp_expired", %{opts: opts} do
    payload = build_event("evt_old")
    ts = @now - 1000
    conn = post_webhook(opts, payload, [{"stripe-signature", header(ts, payload, @secret)}])
    assert conn.status == 401
    assert json_body(conn)["error"] == "timestamp_expired"
  end

  test "far-future timestamp returns timestamp_expired", %{opts: opts} do
    payload = build_event("evt_future")
    ts = @now + 1000
    conn = post_webhook(opts, payload, [{"stripe-signature", header(ts, payload, @secret)}])
    assert conn.status == 401
    assert json_body(conn)["error"] == "timestamp_expired"
  end

  test "wrong secret returns invalid_signature", %{opts: opts} do
    payload = build_event("evt_002")
    conn = post_webhook(opts, payload, [{"stripe-signature", header(@now, payload, "nope")}])
    assert conn.status == 401
    assert json_body(conn)["error"] == "invalid_signature"
  end

  test "tampered body with valid in-window timestamp returns invalid_signature", %{opts: opts} do
    original = build_event("evt_005")
    hdr = header(@now, original, @secret)

    tampered =
      Jason.encode!(%{
        "id" => "evt_005",
        "type" => "charge.completed",
        "data" => %{"amount" => 999_999, "currency" => "usd"}
      })

    conn = post_webhook(opts, tampered, [{"stripe-signature", hdr}])
    assert conn.status == 401
    assert json_body(conn)["error"] == "invalid_signature"
  end

  test "missing header returns invalid_signature", %{opts: opts} do
    conn = post_webhook(opts, build_event("evt_003"), [])
    assert conn.status == 401
    assert json_body(conn)["error"] == "invalid_signature"
  end

  test "empty header returns invalid_signature", %{opts: opts} do
    conn = post_webhook(opts, build_event("evt_004"), [{"stripe-signature", ""}])
    assert conn.status == 401
    assert json_body(conn)["error"] == "invalid_signature"
  end

  test "malformed header (no v1 element) returns invalid_signature", %{opts: opts} do
    conn = post_webhook(opts, build_event("evt_hdr"), [{"stripe-signature", "t=#{@now}"}])
    assert conn.status == 401
    assert json_body(conn)["error"] == "invalid_signature"
  end

  test "non-integer timestamp returns invalid_signature", %{opts: opts} do
    payload = build_event("evt_ts")
    hdr = "t=abc,v1=#{v1(@now, payload, @secret)}"
    conn = post_webhook(opts, payload, [{"stripe-signature", hdr}])
    assert conn.status == 401
    assert json_body(conn)["error"] == "invalid_signature"
  end

  test "duplicate delivery returns duplicate", %{opts: opts, store: store} do
    payload = build_event("evt_010")
    hdr = header(@now, payload, @secret)

    conn1 = post_webhook(opts, payload, [{"stripe-signature", hdr}])
    assert json_body(conn1)["status"] == "received"

    conn2 = post_webhook(opts, payload, [{"stripe-signature", hdr}])
    assert conn2.status == 200
    assert json_body(conn2)["status"] == "duplicate"

    events = WebhookReceiver.Store.all_events(store)
    assert length(Enum.filter(events, &(&1.event_id == "evt_010"))) == 1
  end

  test "malformed JSON returns bad_payload", %{opts: opts} do
    bad = "not json {{"
    conn = post_webhook(opts, bad, [{"stripe-signature", header(@now, bad, @secret)}])
    assert conn.status == 400
    assert json_body(conn)["error"] == "bad_payload"
  end

  test "missing id returns bad_payload", %{opts: opts} do
    payload = Jason.encode!(%{"type" => "charge.completed"})
    conn = post_webhook(opts, payload, [{"stripe-signature", header(@now, payload, @secret)}])
    assert conn.status == 400
    assert json_body(conn)["error"] == "bad_payload"
  end

  test "now option accepts a 0-arity function", %{store: store} do
    opts = [secret: @secret, store: store, now: fn -> @now end]
    payload = build_event("evt_fn")
    conn = post_webhook(opts, payload, [{"stripe-signature", header(@now, payload, @secret)}])
    assert conn.status == 200
    assert json_body(conn)["status"] == "received"
  end

  test "Signature.sign/3 and parse/1 round trip" do
    hdr = "t=#{@now},v1=#{WebhookReceiver.Signature.sign(@now, "hello", @secret)}"
    parsed = WebhookReceiver.Signature.parse(hdr)
    assert parsed["t"] == to_string(@now)
    assert parsed["v1"] == WebhookReceiver.Signature.sign(@now, "hello", @secret)
  end

  test "Signature.parse/1 returns empty map for non-binary" do
    assert WebhookReceiver.Signature.parse(nil) == %{}
  end

  test "GET to webhook path returns 404 or 405", %{opts: opts} do
    conn = do_request(opts, :get, "/api/webhooks/stripe", "")
    assert conn.status in [404, 405]
  end

  test "POST to unknown path returns 404", %{opts: opts} do
    payload = build_event("evt_999")
    conn =
      do_request(opts, :post, "/api/webhooks/unknown", payload, [
        {"stripe-signature", header(@now, payload, @secret)}
      ])

    assert conn.status == 404
  end
end