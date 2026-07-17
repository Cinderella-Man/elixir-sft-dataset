defmodule WebhookReceiverOrderedTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  @secret "whsec_ordered_secret"

  defp sign(payload, secret) do
    :crypto.mac(:hmac, :sha256, secret, payload) |> Base.encode16(case: :lower)
  end

  defp build_event(id, sid, seq, type \\ "charge.completed") do
    Jason.encode!(%{"id" => id, "stream_id" => sid, "sequence" => seq, "type" => type})
  end

  defp json_body(conn), do: Jason.decode!(conn.resp_body)

  setup do
    {:ok, store} = WebhookReceiver.MemoryStore.start_link([])
    %{store: store, opts: [secret: @secret, store: store]}
  end

  defp do_request(opts, method, path, payload, headers \\ []) do
    conn = conn(method, path, payload)

    conn =
      Enum.reduce(headers, conn, fn {k, v}, acc -> put_req_header(acc, k, v) end)

    conn = put_req_header(conn, "content-type", "application/json")
    WebhookReceiver.Router.call(conn, WebhookReceiver.Router.init(opts))
  end

  defp post_signed(opts, payload) do
    do_request(opts, :post, "/api/webhooks/stripe", payload, [
      {"stripe-signature", sign(payload, @secret)}
    ])
  end

  defp deliver(opts, id, sid, seq) do
    post_signed(opts, build_event(id, sid, seq))
  end

  test "in-order deliveries are all received", %{opts: opts, store: store} do
    for seq <- 1..3 do
      conn = deliver(opts, "e#{seq}", "s1", seq)
      assert conn.status == 200
      assert json_body(conn)["status"] == "received"
    end

    assert WebhookReceiver.Store.last_sequence(store, "s1") == 3
    seqs = WebhookReceiver.Store.delivered_events(store, "s1") |> Enum.map(& &1.sequence)
    assert seqs == [1, 2, 3]
    assert WebhookReceiver.Store.buffered_sequences(store, "s1") == []
  end

  test "delivered events are marked :delivered", %{opts: opts, store: store} do
    assert deliver(opts, "e1", "s1", 1).status == 200
    [event] = WebhookReceiver.Store.delivered_events(store, "s1")
    assert event.status == :delivered
    assert event.event_id == "e1"
  end

  test "future event buffered (202) then drained when gap fills", %{opts: opts, store: store} do
    assert json_body(deliver(opts, "e1", "s1", 1))["status"] == "received"

    conn3 = deliver(opts, "e3", "s1", 3)
    assert conn3.status == 202
    assert json_body(conn3)["status"] == "buffered"
    assert WebhookReceiver.Store.last_sequence(store, "s1") == 1
    assert WebhookReceiver.Store.buffered_sequences(store, "s1") == [3]

    conn2 = deliver(opts, "e2", "s1", 2)
    assert conn2.status == 200
    assert json_body(conn2)["status"] == "received"

    assert WebhookReceiver.Store.last_sequence(store, "s1") == 3
    assert WebhookReceiver.Store.buffered_sequences(store, "s1") == []
    seqs = WebhookReceiver.Store.delivered_events(store, "s1") |> Enum.map(& &1.sequence)
    assert seqs == [1, 2, 3]
  end

  test "long gap drains multiple buffered events in order", %{opts: opts, store: store} do
    assert deliver(opts, "e1", "s1", 1).status == 200
    assert deliver(opts, "e4", "s1", 4).status == 202
    assert deliver(opts, "e3", "s1", 3).status == 202
    assert deliver(opts, "e2", "s1", 2).status == 200

    assert WebhookReceiver.Store.last_sequence(store, "s1") == 4
    seqs = WebhookReceiver.Store.delivered_events(store, "s1") |> Enum.map(& &1.sequence)
    assert seqs == [1, 2, 3, 4]
  end

  test "already-delivered sequence returns duplicate", %{opts: opts, store: store} do
    assert deliver(opts, "e1", "s1", 1).status == 200
    conn = deliver(opts, "e1", "s1", 1)
    assert conn.status == 200
    assert json_body(conn)["status"] == "duplicate"
    assert WebhookReceiver.Store.last_sequence(store, "s1") == 1
  end

  test "re-sending an already-buffered sequence returns duplicate", %{opts: opts, store: store} do
    assert deliver(opts, "e1", "s1", 1).status == 200
    assert deliver(opts, "e3", "s1", 3).status == 202

    conn = deliver(opts, "e3", "s1", 3)
    assert conn.status == 200
    assert json_body(conn)["status"] == "duplicate"
    assert WebhookReceiver.Store.buffered_sequences(store, "s1") == [3]
  end

  test "streams are independent", %{opts: opts, store: store} do
    assert deliver(opts, "a1", "sa", 1).status == 200
    assert deliver(opts, "b3", "sb", 3).status == 202

    assert WebhookReceiver.Store.last_sequence(store, "sa") == 1
    assert WebhookReceiver.Store.last_sequence(store, "sb") == 0
    assert WebhookReceiver.Store.buffered_sequences(store, "sb") == [3]
  end

  test "invalid signature returns 401", %{opts: opts} do
    payload = build_event("e1", "s1", 1)

    conn =
      do_request(opts, :post, "/api/webhooks/stripe", payload, [
        {"stripe-signature", sign(payload, "wrong")}
      ])

    assert conn.status == 401
    assert json_body(conn)["error"] == "invalid_signature"
  end

  test "missing stream_id returns bad_payload", %{opts: opts} do
    payload = Jason.encode!(%{"id" => "e1", "sequence" => 1})
    conn = post_signed(opts, payload)
    assert conn.status == 400
    assert json_body(conn)["error"] == "bad_payload"
  end

  test "missing sequence returns bad_payload", %{opts: opts} do
    payload = Jason.encode!(%{"id" => "e1", "stream_id" => "s1"})
    conn = post_signed(opts, payload)
    assert conn.status == 400
    assert json_body(conn)["error"] == "bad_payload"
  end

  test "non-integer sequence returns bad_payload", %{opts: opts} do
    payload = Jason.encode!(%{"id" => "e1", "stream_id" => "s1", "sequence" => "3"})
    conn = post_signed(opts, payload)
    assert conn.status == 400
    assert json_body(conn)["error"] == "bad_payload"
  end

  test "malformed JSON returns bad_payload", %{opts: opts} do
    conn = post_signed(opts, "not json {{")
    assert conn.status == 400
    assert json_body(conn)["error"] == "bad_payload"
  end

  test "Store.deliver/2 directly buffers and drains", %{store: store} do
    e1 = %{event_id: "e1", stream_id: "z", sequence: 1, payload: %{}, status: :pending}
    e2 = %{event_id: "e2", stream_id: "z", sequence: 2, payload: %{}, status: :pending}

    assert {:ok, :buffered} = WebhookReceiver.Store.deliver(store, e2)
    assert {:ok, :received} = WebhookReceiver.Store.deliver(store, e1)
    assert WebhookReceiver.Store.last_sequence(store, "z") == 2
  end

  test "Signature.verify/3 basics" do
    assert :ok = WebhookReceiver.Signature.verify("p", sign("p", @secret), @secret)
    assert :error = WebhookReceiver.Signature.verify("p", "deadbeef", @secret)
    assert :error = WebhookReceiver.Signature.verify(nil, "x", @secret)
  end

  test "GET to webhook path returns 404 or 405", %{opts: opts} do
    conn = do_request(opts, :get, "/api/webhooks/stripe", "")
    assert conn.status in [404, 405]
  end

  test "drained buffered events are marked :delivered, not :pending", %{
    opts: opts,
    store: store
  } do
    assert deliver(opts, "e1", "s1", 1).status == 200
    assert deliver(opts, "e3", "s1", 3).status == 202
    assert deliver(opts, "e4", "s1", 4).status == 202
    assert deliver(opts, "e2", "s1", 2).status == 200

    events = WebhookReceiver.Store.delivered_events(store, "s1")
    assert Enum.map(events, & &1.sequence) == [1, 2, 3, 4]
    assert Enum.map(events, & &1.status) == [:delivered, :delivered, :delivered, :delivered]
  end

  test "events drained via Store.deliver/2 are marked :delivered", %{store: store} do
    e1 = %{event_id: "d1", stream_id: "z", sequence: 1, payload: %{}, status: :pending}
    e2 = %{event_id: "d2", stream_id: "z", sequence: 2, payload: %{}, status: :pending}

    assert {:ok, :buffered} = WebhookReceiver.Store.deliver(store, e2)
    assert {:ok, :received} = WebhookReceiver.Store.deliver(store, e1)

    events = WebhookReceiver.Store.delivered_events(store, "z")
    assert Enum.map(events, & &1.event_id) == ["d1", "d2"]
    assert Enum.map(events, & &1.status) == [:delivered, :delivered]
  end

  test "missing stripe-signature header returns 401", %{opts: opts, store: store} do
    payload = build_event("e1", "s1", 1)
    conn = do_request(opts, :post, "/api/webhooks/stripe", payload, [])

    assert conn.status == 401
    assert json_body(conn)["error"] == "invalid_signature"
    assert WebhookReceiver.Store.last_sequence(store, "s1") == 0
    assert WebhookReceiver.Store.delivered_events(store, "s1") == []
  end

  test "empty stripe-signature header returns 401", %{opts: opts, store: store} do
    payload = build_event("e1", "s1", 1)

    conn =
      do_request(opts, :post, "/api/webhooks/stripe", payload, [{"stripe-signature", ""}])

    assert conn.status == 401
    assert json_body(conn)["error"] == "invalid_signature"
    assert WebhookReceiver.Store.last_sequence(store, "s1") == 0
    assert WebhookReceiver.Store.delivered_events(store, "s1") == []
  end

  test "drain stops at the first gap and leaves later events buffered", %{
    opts: opts,
    store: store
  } do
    assert deliver(opts, "e1", "s1", 1).status == 200
    assert deliver(opts, "e3", "s1", 3).status == 202
    assert deliver(opts, "e5", "s1", 5).status == 202

    assert json_body(deliver(opts, "e2", "s1", 2))["status"] == "received"

    assert WebhookReceiver.Store.last_sequence(store, "s1") == 3
    assert WebhookReceiver.Store.buffered_sequences(store, "s1") == [5]

    events = WebhookReceiver.Store.delivered_events(store, "s1")
    assert Enum.map(events, & &1.sequence) == [1, 2, 3]
    assert Enum.map(events, & &1.status) == [:delivered, :delivered, :delivered]
  end

  test "buffered_sequences returns sorted seqs regardless of arrival order", %{
    opts: opts,
    store: store
  } do
    assert deliver(opts, "e1", "s1", 1).status == 200
    assert deliver(opts, "e7", "s1", 7).status == 202
    assert deliver(opts, "e3", "s1", 3).status == 202
    assert deliver(opts, "e5", "s1", 5).status == 202

    assert WebhookReceiver.Store.buffered_sequences(store, "s1") == [3, 5, 7]
    assert WebhookReceiver.Store.last_sequence(store, "s1") == 1
  end

  test "missing id and non-string id both return bad_payload", %{opts: opts, store: store} do
    missing = Jason.encode!(%{"stream_id" => "s1", "sequence" => 1})
    conn = post_signed(opts, missing)
    assert conn.status == 400
    assert json_body(conn)["error"] == "bad_payload"

    wrong = Jason.encode!(%{"id" => 42, "stream_id" => "s1", "sequence" => 1})
    conn = post_signed(opts, wrong)
    assert conn.status == 400
    assert json_body(conn)["error"] == "bad_payload"

    assert WebhookReceiver.Store.last_sequence(store, "s1") == 0
    assert WebhookReceiver.Store.delivered_events(store, "s1") == []
  end

  test "non-string stream_id returns bad_payload", %{opts: opts, store: store} do
    payload = Jason.encode!(%{"id" => "e1", "stream_id" => 7, "sequence" => 1})
    conn = post_signed(opts, payload)

    assert conn.status == 400
    assert json_body(conn)["error"] == "bad_payload"
    assert WebhookReceiver.Store.last_sequence(store, "s1") == 0
  end

  test "sequence strictly below last_seq is duplicate and does not re-deliver", %{
    opts: opts,
    store: store
  } do
    for seq <- 1..3, do: assert(deliver(opts, "e#{seq}", "s1", seq).status == 200)

    conn = deliver(opts, "e1-again", "s1", 1)
    assert conn.status == 200
    assert json_body(conn)["status"] == "duplicate"

    assert WebhookReceiver.Store.last_sequence(store, "s1") == 3
    assert WebhookReceiver.Store.buffered_sequences(store, "s1") == []

    events = WebhookReceiver.Store.delivered_events(store, "s1")
    assert Enum.map(events, & &1.event_id) == ["e1", "e2", "e3"]
  end

  test "Signature.verify/3 rejects non-binary signature and secret" do
    assert :error = WebhookReceiver.Signature.verify("p", nil, @secret)
    assert :error = WebhookReceiver.Signature.verify("p", :bad, @secret)
    assert :error = WebhookReceiver.Signature.verify("p", sign("p", @secret), nil)
    assert :error = WebhookReceiver.Signature.verify("p", sign("p", @secret), 123)
  end
end
