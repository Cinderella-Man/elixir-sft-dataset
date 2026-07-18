  test "Signature.verify/3 basics" do
    assert :ok = WebhookReceiver.Signature.verify("p", sign("p", @secret), @secret)
    assert :error = WebhookReceiver.Signature.verify("p", "deadbeef", @secret)
    assert :error = WebhookReceiver.Signature.verify(nil, "x", @secret)
  end