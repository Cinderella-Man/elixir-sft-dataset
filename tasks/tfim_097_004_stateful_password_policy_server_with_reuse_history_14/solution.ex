  test "username similarity rejects at distance 3 and accepts at distance 4 by default" do
    {:ok, pid} = PasswordPolicy.start_link([])

    # "abcdefg1!" -> "abcdefg1!xyz" is 3 insertions: distance 3, and the rule
    # fires on distance <= :max_username_similarity (default 3).
    assert PasswordPolicy.set_password(pid, "abcdefg1!xyz", "Abcdefg1!") ==
             {:error, [:too_similar_to_username]}

    # One character further away: distance 4 > 3, so the password is accepted.
    assert PasswordPolicy.set_password(pid, "abcdefg1!wxyz", "Abcdefg1!") == :ok
  end