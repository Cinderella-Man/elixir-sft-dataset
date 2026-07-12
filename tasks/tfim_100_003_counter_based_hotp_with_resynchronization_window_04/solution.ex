  test "generate_code reproduces the RFC 4226 Appendix D vectors" do
    for {counter, expected} <- @rfc_codes do
      assert HOTP.generate_code(@secret, counter) == expected,
             "counter #{counter} should be #{expected}"
    end
  end