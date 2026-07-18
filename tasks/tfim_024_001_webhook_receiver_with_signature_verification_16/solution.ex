  test "Signature.verify/3 returns :error for wrong signature" do
    payload = "hello"
    sig = sign(payload, "other_secret")
    assert :error = WebhookReceiver.Signature.verify(payload, sig, @secret)
  end