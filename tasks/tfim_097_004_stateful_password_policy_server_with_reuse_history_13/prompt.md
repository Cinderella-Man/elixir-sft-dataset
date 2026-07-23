# One test is missing its body

Module plus harness below; a single `test` body was replaced with
`# TODO`. Reconstruct it from its name and the surrounding suite so the
harness passes for a correct implementation of the module. Touch nothing
else.

## Module under test

```elixir
defmodule PasswordPolicy do
  @moduledoc """
  A GenServer that enforces a password policy and remembers each user's most
  recent accepted passwords to forbid reuse across changes.

  ## Usage

      {:ok, pid} = PasswordPolicy.start_link(history_size: 3)
      PasswordPolicy.set_password(pid, "alice", "Tr0ub4dor&3")  # => :ok
      PasswordPolicy.set_password(pid, "alice", "Tr0ub4dor&3")  # => {:error, [:reused_password]}
  """

  use GenServer

  @default_history_size 5

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    case name do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @spec set_password(GenServer.server(), String.t(), String.t()) :: :ok | {:error, [atom()]}
  def set_password(server, username, password) do
    GenServer.call(server, {:set_password, username, password})
  end

  @spec history_count(GenServer.server(), String.t()) :: non_neg_integer()
  def history_count(server, username) do
    GenServer.call(server, {:history_count, username})
  end

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  def init(opts) do
    opts_map = Map.new(opts)

    state = %{
      history_size: Map.get(opts_map, :history_size, @default_history_size),
      policy: build_policy(opts_map),
      users: %{}
    }

    {:ok, state}
  end

  def handle_call({:set_password, username, password}, _from, state) do
    history = Map.get(state.users, username, [])

    case violations(password, username, history, state.policy) do
      [] ->
        new_history = Enum.take([password | history], state.history_size)
        users = Map.put(state.users, username, new_history)
        {:reply, :ok, %{state | users: users}}

      list ->
        {:reply, {:error, list}, state}
    end
  end

  def handle_call({:history_count, username}, _from, state) do
    {:reply, length(Map.get(state.users, username, [])), state}
  end

  # ---------------------------------------------------------------------------
  # Config
  # ---------------------------------------------------------------------------

  defp build_policy(opts) do
    %{
      min_length: Map.get(opts, :min_length, 8),
      max_length: Map.get(opts, :max_length, 128),
      require_uppercase: Map.get(opts, :require_uppercase, true),
      require_lowercase: Map.get(opts, :require_lowercase, true),
      require_digit: Map.get(opts, :require_digit, true),
      require_special: Map.get(opts, :require_special, true),
      common_passwords: Map.get(opts, :common_passwords, []),
      max_username_similarity: Map.get(opts, :max_username_similarity, 3)
    }
  end

  # ---------------------------------------------------------------------------
  # Validation (canonical rule order)
  # ---------------------------------------------------------------------------

  defp violations(password, username, history, policy) do
    cfg = Map.merge(policy, %{username: username, history: history})

    [
      &check_min_length/2,
      &check_max_length/2,
      &check_uppercase/2,
      &check_lowercase/2,
      &check_digit/2,
      &check_special/2,
      &check_common/2,
      &check_reuse/2,
      &check_username_similarity/2
    ]
    |> Enum.reduce([], fn check, acc ->
      case check.(password, cfg) do
        :ok -> acc
        {:violation, v} -> [v | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp check_min_length(password, %{min_length: min}) do
    if String.length(password) >= min, do: :ok, else: {:violation, :too_short}
  end

  defp check_max_length(password, %{max_length: max}) do
    if String.length(password) <= max, do: :ok, else: {:violation, :too_long}
  end

  defp check_uppercase(_password, %{require_uppercase: false}), do: :ok

  defp check_uppercase(password, _cfg) do
    if String.match?(password, ~r/[A-Z]/), do: :ok, else: {:violation, :no_uppercase}
  end

  defp check_lowercase(_password, %{require_lowercase: false}), do: :ok

  defp check_lowercase(password, _cfg) do
    if String.match?(password, ~r/[a-z]/), do: :ok, else: {:violation, :no_lowercase}
  end

  defp check_digit(_password, %{require_digit: false}), do: :ok

  defp check_digit(password, _cfg) do
    if String.match?(password, ~r/[0-9]/), do: :ok, else: {:violation, :no_digit}
  end

  defp check_special(_password, %{require_special: false}), do: :ok

  defp check_special(password, _cfg) do
    if String.match?(password, ~r/[^a-zA-Z0-9]/), do: :ok, else: {:violation, :no_special}
  end

  defp check_common(password, %{common_passwords: list}) do
    lower = String.downcase(password)

    if Enum.any?(list, fn p -> String.downcase(p) == lower end),
      do: {:violation, :common_password},
      else: :ok
  end

  defp check_reuse(password, %{history: history}) do
    if password in history, do: {:violation, :reused_password}, else: :ok
  end

  defp check_username_similarity(password, %{
         username: username,
         max_username_similarity: threshold
       }) do
    dist = levenshtein(String.downcase(password), String.downcase(username))
    if dist > threshold, do: :ok, else: {:violation, :too_similar_to_username}
  end

  # ---------------------------------------------------------------------------
  # Levenshtein distance — iterative two-row dynamic programming.
  # ---------------------------------------------------------------------------

  @doc false
  @spec levenshtein(String.t(), String.t()) :: non_neg_integer()
  def levenshtein(a, b) when is_binary(a) and is_binary(b) do
    a_graphs = String.graphemes(a)
    b_graphs = String.graphemes(b)

    {a_graphs, b_graphs} =
      if length(a_graphs) < length(b_graphs),
        do: {b_graphs, a_graphs},
        else: {a_graphs, b_graphs}

    m = length(a_graphs)
    n = length(b_graphs)

    cond do
      m == 0 -> n
      n == 0 -> m
      true -> do_levenshtein(a_graphs, b_graphs, n)
    end
  end

  defp do_levenshtein(a_graphs, b_graphs, n) do
    prev = Enum.to_list(0..n) |> List.to_tuple()

    a_graphs
    |> Enum.with_index(1)
    |> Enum.reduce(prev, fn {a_char, i}, prev_row ->
      b_graphs
      |> Enum.with_index(1)
      |> Enum.reduce({[i], i}, fn {b_char, j}, {acc, left} ->
        diag = elem(prev_row, j - 1)
        up = elem(prev_row, j)
        cost = if a_char == b_char, do: 0, else: 1

        val = Enum.min([left + 1, up + 1, diag + cost])
        {[val | acc], val}
      end)
      |> elem(0)
      |> Enum.reverse()
      |> List.to_tuple()
    end)
    |> elem(n)
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
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
    # TODO
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

  test "the :name option registers the server so calls can be made through the name" do
    name = :password_policy_named_server_test
    {:ok, pid} = PasswordPolicy.start_link(name: name)

    assert Process.whereis(name) == pid

    # Both public calls must work through the registered name.
    assert PasswordPolicy.set_password(name, "alice", "Tr0ub4dor&3") == :ok
    assert PasswordPolicy.history_count(name, "alice") == 1

    # The name and the pid address the same server state.
    assert PasswordPolicy.set_password(pid, "alice", "Tr0ub4dor&3") ==
             {:error, [:reused_password]}
  end
end
```
