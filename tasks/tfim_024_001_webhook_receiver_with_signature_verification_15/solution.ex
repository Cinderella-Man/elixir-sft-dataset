  test "Signature.verify/3 returns :ok for correct signature" do
    payload = "hello"
    sig = sign(payload, @secret)
    assert :ok = WebhookReceiver.Signature.verify(payload, sig, @secret)
  end