  test "parse accepts each supported algorithm spelling case-insensitively" do
    assert config!(secret: @sha1_secret, algorithm: "sha1").algorithm == :sha1
    assert config!(secret: @sha256_secret, algorithm: "Sha256").algorithm == :sha256
    assert config!(secret: @sha512_secret, algorithm: "SHA512").algorithm == :sha512
  end