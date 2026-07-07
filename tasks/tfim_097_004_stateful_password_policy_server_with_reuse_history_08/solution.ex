  test "unknown user has an empty history" do
    {:ok, pid} = PasswordPolicy.start_link([])
    assert PasswordPolicy.history_count(pid, "nobody") == 0
  end