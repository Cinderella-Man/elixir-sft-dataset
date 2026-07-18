  test "similarity uses true edit distance for substitutions, deletions and 1-char names" do
    {:ok, pid} =
      PasswordPolicy.start_link(
        min_length: 1,
        require_uppercase: false,
        require_lowercase: false,
        require_digit: false,
        require_special: false
      )

    # distance("abcd", "a") == 3 (three deletions) -> too similar.
    assert PasswordPolicy.set_password(pid, "a", "abcd") ==
             {:error, [:too_similar_to_username]}

    # distance("abcdexyz", "abcdefgh") == 3 (three substitutions) -> too similar.
    assert PasswordPolicy.set_password(pid, "abcdefgh", "abcdexyz") ==
             {:error, [:too_similar_to_username]}

    # distance("zabcdefghxyz", "abcdefgh") == 4 (drop "z" and "xyz") -> accepted.
    assert PasswordPolicy.set_password(pid, "abcdefgh", "zabcdefghxyz") == :ok
  end