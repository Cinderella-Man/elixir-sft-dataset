  test "Signature.verify/3 returns :error for garbage signature" do
    assert :error = WebhookReceiver.Signature.verify("hello", "not_hex_at_all!", @secret)
  end