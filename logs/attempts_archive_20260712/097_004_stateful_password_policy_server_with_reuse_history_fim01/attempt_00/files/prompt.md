Implement the private `violations/4` function.

`violations(password, username, history, policy)` runs every password-policy
rule against `password` and returns a list of the failing rule atoms, in the
canonical order below. If the password passes every rule, it returns an empty
list `[]`.

It must gather the per-request context the individual checks need — the
`username` and the user's `history` — together with the fields already present
in `policy`. The existing check helpers (`check_min_length/2`,
`check_max_length/2`, `check_uppercase/2`, `check_lowercase/2`, `check_digit/2`,
`check_special/2`, `check_common/2`, `check_reuse/2`,
`check_username_similarity/2`) each take `(password, cfg)` and return either
`:ok` or `{:violation, atom}`, where `cfg` is a single map. So merge `policy`
with `%{username: username, history: history}` to form that `cfg` map.

Apply the checks in this canonical order and collect the violation atoms in the
same order:

1. `:too_short`
2. `:too_long`
3. `:no_uppercase`
4. `:no_lowercase`
5. `:no_digit`
6. `:no_special`
7. `:common_password`
8. `:reused_password`
9. `:too_similar_to_username`

Every failing rule must be reported (do not stop at the first failure), and the
returned list must preserve the canonical order above.

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
    # TODO
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