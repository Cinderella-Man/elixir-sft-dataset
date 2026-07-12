  test "adjacent counters produce different codes" do
    refute HOTP.generate_code(@secret, 0) == HOTP.generate_code(@secret, 1)
  end