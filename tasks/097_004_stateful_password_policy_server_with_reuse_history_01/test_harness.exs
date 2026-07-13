defmodule PasswordPolicyV3Test do
  use ExUnit.Case, async: false

  # Exercises the stateful GenServer variant of PasswordPolicy: policy enforcement
  # plus bounded per-user reuse history.

  test "accepts a strong new password and records it in history" do
    {:ok, pid} = PasswordPolicy.start_link([])

    assert PasswordPolicy.set_password(pid, "alice", "Tr0ub4dor&3") == :ok
    assert PasswordPolicy.history_count(pid, "alice") == 1
  end

  test "rejects reuse of a remembered password without touching history" do
    {:ok, pid} = PasswordPolicy.start_link([])

    assert PasswordPolicy.set_password(pid, "alice", "Secret9!x") == :ok
    assert PasswordPolicy.set_password(pid, "alice", "Secret9!x") == {:error, [:reused_password]}
    assert PasswordPolicy.history_count(pid, "alice") == 1
  end

  test "history is bounded by :history_size and evicts the oldest" do
    {:ok, pid} = PasswordPolicy.start_link(history_size: 2)

    assert PasswordPolicy.set_password(pid, "carol", "Aaa111!!x") == :ok
    assert PasswordPolicy.set_password(pid, "carol", "Bbb222!!x") == :ok
    assert PasswordPolicy.set_password(pid, "carol", "Ccc333!!x") == :ok

    # Only the two most recent (Ccc, Bbb) are remembered; Aaa has been evicted.
    assert PasswordPolicy.history_count(pid, "carol") == 2
    assert PasswordPolicy.set_password(pid, "carol", "Bbb222!!x") == {:error, [:reused_password]}
    assert PasswordPolicy.set_password(pid, "carol", "Aaa111!!x") == :ok
  end

  test "policy violations are reported in canonical order and not recorded" do
    {:ok, pid} = PasswordPolicy.start_link([])

    assert PasswordPolicy.set_password(pid, "operator", "abc") ==
             {:error, [:too_short, :no_uppercase, :no_digit, :no_special]}

    assert PasswordPolicy.history_count(pid, "operator") == 0
  end

  test "common-password blocklist from startup config is enforced" do
    {:ok, pid} = PasswordPolicy.start_link(common_passwords: ["letmein1!"])

    assert PasswordPolicy.set_password(pid, "operator", "Letmein1!") ==
             {:error, [:common_password]}
  end

  test "per-user histories are independent" do
    {:ok, pid} = PasswordPolicy.start_link([])

    assert PasswordPolicy.set_password(pid, "alice", "Secret9!x") == :ok
    # bob has never used it, so it is fine for bob...
    assert PasswordPolicy.set_password(pid, "bob", "Secret9!x") == :ok
    # ...but alice still cannot reuse her own.
    assert PasswordPolicy.set_password(pid, "alice", "Secret9!x") == {:error, [:reused_password]}
  end

  test "unknown user has an empty history" do
    {:ok, pid} = PasswordPolicy.start_link([])
    assert PasswordPolicy.history_count(pid, "nobody") == 0
  end

  # --------------------------------------------------------------------------
  # Added tests. Each pins a documented default or rule boundary that the
  # blocks above leave unconstrained. Everything is observed through the
  # public API (start_link/set_password/history_count) only.
  #
  # Note: the reference orders the two strings by length before running the DP.
  # Levenshtein distance is symmetric, so that ordering is not observable
  # through the API and is deliberately left unpinned.
  # --------------------------------------------------------------------------

  test "default :history_size remembers exactly five passwords" do
    {:ok, pid} = PasswordPolicy.start_link([])

    for pw <- ~w(P1!aaaaa P2!bbbbb P3!ccccc P4!ddddd P5!eeeee) do
      assert PasswordPolicy.set_password(pid, "operator", pw) == :ok
    end

    # Five accepted passwords all fit inside the default bound.
    assert PasswordPolicy.history_count(pid, "operator") == 5

    # A sixth evicts the oldest but keeps the bound at five.
    assert PasswordPolicy.set_password(pid, "operator", "P6!fffff") == :ok
    assert PasswordPolicy.history_count(pid, "operator") == 5

    # The second-oldest is still remembered; the oldest has been evicted.
    assert PasswordPolicy.set_password(pid, "operator", "P2!bbbbb") ==
             {:error, [:reused_password]}

    assert PasswordPolicy.set_password(pid, "operator", "P1!aaaaa") == :ok
  end

  test ":min_length defaults to 8, so a 7-character password is :too_short" do
    {:ok, pid} = PasswordPolicy.start_link([])

    assert PasswordPolicy.set_password(pid, "operator", "Ab1!xyz") ==
             {:error, [:too_short]}

    # The same password one character longer sits exactly on the bound.
    assert PasswordPolicy.set_password(pid, "operator", "Ab1!xyzw") == :ok
  end

  test ":max_length defaults to 128, so 128 chars pass and 129 are :too_long" do
    {:ok, pid} = PasswordPolicy.start_link([])

    at_limit = "Aa1!" <> String.duplicate("x", 124)
    over_limit = "Aa1!" <> String.duplicate("x", 125)

    assert String.length(at_limit) == 128
    assert String.length(over_limit) == 129

    assert PasswordPolicy.set_password(pid, "operator", at_limit) == :ok

    assert PasswordPolicy.set_password(pid, "operator", over_limit) ==
             {:error, [:too_long]}
  end

  test "lowercase is required by default" do
    {:ok, pid} = PasswordPolicy.start_link([])

    assert PasswordPolicy.set_password(pid, "operator", "ABC123!@") ==
             {:error, [:no_lowercase]}

    assert PasswordPolicy.history_count(pid, "operator") == 0
  end

  test "require_* set to false skips exactly the matching character-class checks" do
    {:ok, pid} =
      PasswordPolicy.start_link(
        require_uppercase: false,
        require_lowercase: false,
        require_digit: false,
        require_special: false
      )

    # Digits only: no uppercase, no lowercase, no special -- all four checks
    # are switched off, so this is accepted and recorded.
    assert PasswordPolicy.set_password(pid, "operator", "12345678") == :ok
    assert PasswordPolicy.history_count(pid, "operator") == 1
  end

  test "username similarity rejects at distance 3 and accepts at distance 4 by default" do
    {:ok, pid} = PasswordPolicy.start_link([])

    # "abcdefg1!" -> "abcdefg1!xyz" is 3 insertions: distance 3, and the rule
    # fires on distance <= :max_username_similarity (default 3).
    assert PasswordPolicy.set_password(pid, "abcdefg1!xyz", "Abcdefg1!") ==
             {:error, [:too_similar_to_username]}

    # One character further away: distance 4 > 3, so the password is accepted.
    assert PasswordPolicy.set_password(pid, "abcdefg1!wxyz", "Abcdefg1!") == :ok
  end

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

  test "a transposed username stays 3 edits away and clears a :max_username_similarity of 2" do
    {:ok, pid} =
      PasswordPolicy.start_link(
        min_length: 1,
        max_username_similarity: 2,
        require_uppercase: false,
        require_lowercase: false,
        require_digit: false,
        require_special: false
      )

    # distance("badc", "abcd") == 3: swapping two adjacent pairs costs three
    # edits under Levenshtein, not two. 3 > 2, so this is accepted.
    assert PasswordPolicy.set_password(pid, "abcd", "badc") == :ok
    assert PasswordPolicy.history_count(pid, "abcd") == 1
  end
end
