  test "Signature.parse/1 returns empty map for non-binary" do
    assert WebhookReceiver.Signature.parse(nil) == %{}
  end