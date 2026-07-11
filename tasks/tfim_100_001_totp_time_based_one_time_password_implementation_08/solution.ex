  test "code changes at a step boundary" do
    secret = TOTP.generate_secret()
    # Use a deterministic step boundary
    t = 30 * 1000

    code_before = TOTP.generate_code(secret, t - 1)
    code_after = TOTP.generate_code(secret, t)

    # There is a 1-in-1_000_000 chance these are equal by coincidence.
    # Acceptable for a test suite.
    refute code_before == code_after
  end