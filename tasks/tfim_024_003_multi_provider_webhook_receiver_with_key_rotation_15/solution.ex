  test "Signature.verify/4 returns :error for non-binary input" do
    assert :error = WebhookReceiver.Signature.verify(nil, "x", "y")
  end