  test "token is URL-safe (no +, /, or = characters)" do
    token = seal("hello", @key, 60)
    refute String.contains?(token, "+")
    refute String.contains?(token, "/")
    refute String.contains?(token, "=")
  end