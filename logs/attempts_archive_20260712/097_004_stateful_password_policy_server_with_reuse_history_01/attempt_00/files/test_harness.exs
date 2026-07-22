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
end