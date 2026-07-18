  test "generate_secret encodes exactly 160 bits as 32 unpadded base32 characters" do
    for _ <- 1..10 do
      secret = TOTP.generate_secret()
      assert byte_size(secret) == 32
      refute String.contains?(secret, "=")
      assert String.match?(secret, ~r/\A[A-Z2-7]{32}\z/)
    end
  end