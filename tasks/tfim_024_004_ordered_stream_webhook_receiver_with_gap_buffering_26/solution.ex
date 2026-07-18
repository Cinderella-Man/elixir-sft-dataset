  test "Signature.verify/3 rejects non-binary signature and secret" do
    assert :error = WebhookReceiver.Signature.verify("p", nil, @secret)
    assert :error = WebhookReceiver.Signature.verify("p", :bad, @secret)
    assert :error = WebhookReceiver.Signature.verify("p", sign("p", @secret), nil)
    assert :error = WebhookReceiver.Signature.verify("p", sign("p", @secret), 123)
  end