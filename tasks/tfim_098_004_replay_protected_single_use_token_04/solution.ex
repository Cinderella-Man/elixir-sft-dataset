  test "token is URL-safe (no +, /, or = characters)", %{server: server} do
    token = SingleUseToken.issue(server, "hello", 60)
    refute String.contains?(token, "+")
    refute String.contains?(token, "/")
    refute String.contains?(token, "=")
  end