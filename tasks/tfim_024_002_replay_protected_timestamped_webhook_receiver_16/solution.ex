  test "Signature.sign/3 and parse/1 round trip" do
    hdr = "t=#{@now},v1=#{WebhookReceiver.Signature.sign(@now, "hello", @secret)}"
    parsed = WebhookReceiver.Signature.parse(hdr)
    assert parsed["t"] == to_string(@now)
    assert parsed["v1"] == WebhookReceiver.Signature.sign(@now, "hello", @secret)
  end