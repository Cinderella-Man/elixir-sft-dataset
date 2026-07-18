  test "Signature.verify_any/4 succeeds on any matching secret" do
    payload = "hello"
    hex = :crypto.mac(:hmac, :sha256, @gh_old, payload) |> Base.encode16(case: :lower)
    sig = "sha256=" <> hex
    assert :ok = WebhookReceiver.Signature.verify_any(payload, sig, [@gh_new, @gh_old], "sha256=")
    assert :error = WebhookReceiver.Signature.verify_any(payload, sig, [@gh_new], "sha256=")
  end