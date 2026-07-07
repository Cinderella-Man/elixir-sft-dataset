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

    conn =
      post_webhook(opts, "stripe", payload, [{"stripe-signature", stripe_sig(payload, @stripe)}])

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
    payload = build_event("shared_id")

    c1 =
      post_webhook(opts, "stripe", payload, [{"stripe-signature", stripe_sig(payload, @stripe)}])

    c2 =
      post_webhook(opts, "github", payload, [{"x-hub-signature-256", gh_sig(payload, @gh_new)}])

    assert json_body(c1)["status"] == "received"
    assert json_body(c2)["status"] == "received"

    assert {:ok, _} = WebhookReceiver.Store.get_event(store, "stripe", "shared_id")
    assert {:ok, _} = WebhookReceiver.Store.get_event(store, "github", "shared_id")
    assert length(WebhookReceiver.Store.all_events(store)) == 2
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
