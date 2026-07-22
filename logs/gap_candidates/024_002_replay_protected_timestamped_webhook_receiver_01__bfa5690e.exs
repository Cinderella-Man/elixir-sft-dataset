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

  test "expired timestamp with a bad signature reports timestamp_expired", %{opts: opts} do
    payload = build_event("evt_order")
    ts = @now - 1000
    hdr = header(ts, payload, "wrong_secret_entirely")
    conn = post_webhook(opts, payload, [{"stripe-signature", hdr}])
    assert conn.status == 401
    assert json_body(conn)["error"] == "timestamp_expired"
  end

  test "tolerance defaults to 300 seconds when the option is omitted", %{store: store} do
    opts = [secret: @secret, store: store, now: @now]

    inside = build_event("evt_default_in")
    hdr_in = header(@now - 300, inside, @secret)
    conn_in = post_webhook(opts, inside, [{"stripe-signature", hdr_in}])
    assert conn_in.status == 200
    assert json_body(conn_in)["status"] == "received"

    outside = build_event("evt_default_out")
    hdr_out = header(@now - 301, outside, @secret)
    conn_out = post_webhook(opts, outside, [{"stripe-signature", hdr_out}])
    assert conn_out.status == 401
    assert json_body(conn_out)["error"] == "timestamp_expired"
  end

  test "future timestamp exactly at the tolerance edge is accepted, one past it expires",
       %{opts: opts} do
    edge = build_event("evt_future_edge")

    conn_edge =
      post_webhook(opts, edge, [{"stripe-signature", header(@now + 300, edge, @secret)}])

    assert conn_edge.status == 200
    assert json_body(conn_edge)["status"] == "received"

    past = build_event("evt_future_past")

    conn_past =
      post_webhook(opts, past, [{"stripe-signature", header(@now + 301, past, @secret)}])

    assert conn_past.status == 401
    assert json_body(conn_past)["error"] == "timestamp_expired"
  end

  test "Store.store_event/3 reports created then duplicate and keeps first payload",
       %{store: store} do
    assert {:ok, :created} = WebhookReceiver.Store.store_event(store, "evt_sv", %{"n" => 1})
    assert {:ok, :duplicate} = WebhookReceiver.Store.store_event(store, "evt_sv", %{"n" => 2})
    assert {:ok, event} = WebhookReceiver.Store.get_event(store, "evt_sv")
    assert event.payload == %{"n" => 1}
    assert event.status == :pending
    assert length(WebhookReceiver.Store.all_events(store)) == 1
  end

  test "Store.get_event/2 returns :error for an unknown event id", %{store: store} do
    assert WebhookReceiver.Store.get_event(store, "evt_never_stored") == :error
  end

  test "all_events returns every distinct stored event as a list", %{opts: opts, store: store} do
    for id <- ["evt_a1", "evt_a2", "evt_a3"] do
      payload = build_event(id)
      conn = post_webhook(opts, payload, [{"stripe-signature", header(@now, payload, @secret)}])
      assert conn.status == 200
    end

    events = WebhookReceiver.Store.all_events(store)
    assert is_list(events)
    assert Enum.sort(Enum.map(events, & &1.event_id)) == ["evt_a1", "evt_a2", "evt_a3"]
  end

  test "now defaults to the current system time when the option is omitted", %{store: store} do
    opts = [secret: @secret, store: store, tolerance: 300]
    real_now = System.system_time(:second)

    fresh = build_event("evt_sys_now_#{System.pid()}_#{System.unique_integer([:positive])}")
    hdr_fresh = header(real_now, fresh, @secret)
    conn_fresh = post_webhook(opts, fresh, [{"stripe-signature", hdr_fresh}])
    assert conn_fresh.status == 200
    assert json_body(conn_fresh)["status"] == "received"

    stale = build_event("evt_sys_old_#{System.pid()}_#{System.unique_integer([:positive])}")
    hdr_stale = header(real_now - 1000, stale, @secret)
    conn_stale = post_webhook(opts, stale, [{"stripe-signature", hdr_stale}])
    assert conn_stale.status == 401
    assert json_body(conn_stale)["error"] == "timestamp_expired"
  end

  test "default now rejects a fixture timestamp far outside the tolerance window",
       %{store: store} do
    opts = [secret: @secret, store: store, tolerance: 300]
    payload = build_event("evt_sys_fixture_#{System.unique_integer([:positive])}")
    conn = post_webhook(opts, payload, [{"stripe-signature", header(@now, payload, @secret)}])
    assert conn.status == 401
    assert json_body(conn)["error"] == "timestamp_expired"
  end
end
