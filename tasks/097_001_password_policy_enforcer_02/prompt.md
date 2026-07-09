# Task: Implement `do_levenshtein/4`

The module `PasswordPolicy` is complete except for the private helper
`do_levenshtein/4`, which is the dynamic-programming core of the Levenshtein
distance routine. Implement its body.

By the time `do_levenshtein/4` is called, the public `levenshtein/2` wrapper has
already:

- split both inputs into lists of grapheme clusters,
- swapped the arguments so that `a_graphs` is the **longer** (or equal-length)
  list and `b_graphs` is the **shorter** one, and
- handled the empty-string base cases, so both lists are guaranteed non-empty.

`do_levenshtein(a_graphs, b_graphs, _m, n)` receives:

- `a_graphs` — the list of grapheme clusters for the longer string (the rows).
- `b_graphs` — the list of grapheme clusters for the shorter string (the columns).
- `_m` — the length of `a_graphs` (unused here).
- `n` — the length of `b_graphs`.

It must return the Levenshtein (edit) distance between the two strings as a
`non_neg_integer()`, computed with an **iterative two-row dynamic-programming**
approach for `O(m*n)` time and `O(min(m,n))` space:

- Initialise the "previous row" as the distances from the empty string to each
  prefix of `b`, i.e. the values `0, 1, 2, …, n` (representing row `i = 0`).
- Iterate over `a_graphs` with a 1-based row index `i`. For each row, build the
  current row starting with `curr[0] = i` (the distance from the first `i`
  characters of `a` to the empty string).
- For each column `j` (1-based over `b_graphs`), compute the cell as the minimum
  of:
  - deletion: `left + 1` (the cell to the left in the current row, `curr[j-1]`),
  - insertion: `up + 1` (the cell above, `prev[j]`),
  - substitution/match: `diag + cost`, where `diag` is `prev[j-1]` and `cost`
    is `0` when the two graphemes are equal, otherwise `1`.
- The current row becomes the previous row for the next iteration.
- After all rows are processed, the answer is the last cell of the final row
  (index `n`).

Represent each row as a tuple so cells can be read by index with `elem/2`.

```elixir
defmodule PasswordPolicy do
  @moduledoc """
  Validates passwords against a configurable set of rules.

  ## Usage

      context = %{
        username: "alice",
        min_length: 10,
        require_special: true,
        common_passwords: ["password123", "letmein"],
        previous_passwords: ["OldPass1!"]
      }

      PasswordPolicy.validate("NewSecure@99", context)
      # => :ok

      PasswordPolicy.validate("alice", context)
      # => {:error, [:too_short, :no_uppercase, :no_digit, :too_similar_to_username]}
  """

  # ---------------------------------------------------------------------------
  # Defaults
  # ---------------------------------------------------------------------------

  @default_min_length 8
  @default_max_length 128
  @default_require_uppercase true
  @default_require_lowercase true
  @default_require_digit true
  @default_require_special true
  @default_common_passwords []
  @default_previous_passwords []
  @default_max_username_similarity 3

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Validates `password` against the rules encoded in `context`.

  Returns `:ok` when every active rule passes, or
  `{:error, violations}` where `violations` is a list of atoms — one per
  failing rule — in the order the rules are evaluated.

  `context` must include `:username`. All other keys are optional and fall
  back to the module defaults.
  """
  @spec validate(String.t(), map()) :: :ok | {:error, [atom()]}
  def validate(password, %{username: _} = context) do
    cfg = build_config(context)

    violations =
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

    case violations do
      [] -> :ok
      list -> {:error, list}
    end
  end

  def validate(_password, _context) do
    raise ArgumentError, "context map must include the :username key"
  end

  # ---------------------------------------------------------------------------
  # Config assembly
  # ---------------------------------------------------------------------------

  defp build_config(context) do
    %{
      username: Map.fetch!(context, :username),
      min_length: Map.get(context, :min_length, @default_min_length),
      max_length: Map.get(context, :max_length, @default_max_length),
      require_uppercase: Map.get(context, :require_uppercase, @default_require_uppercase),
      require_lowercase: Map.get(context, :require_lowercase, @default_require_lowercase),
      require_digit: Map.get(context, :require_digit, @default_require_digit),
      require_special: Map.get(context, :require_special, @default_require_special),
      common_passwords: Map.get(context, :common_passwords, @default_common_passwords),
      previous_passwords: Map.get(context, :previous_passwords, @default_previous_passwords),
      max_username_similarity:
        Map.get(context, :max_username_similarity, @default_max_username_similarity)
    }
  end

  # ---------------------------------------------------------------------------
  # Individual rule checkers
  # Each returns :ok or {:violation, atom()}.
  # ---------------------------------------------------------------------------

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
    # "special" = any character that is not a-z, A-Z, or 0-9
    if String.match?(password, ~r/[^a-zA-Z0-9]/), do: :ok, else: {:violation, :no_special}
  end

  defp check_common(password, %{common_passwords: list}) do
    lower = String.downcase(password)
    common = Enum.any?(list, fn p -> String.downcase(p) == lower end)
    if common, do: {:violation, :common_password}, else: :ok
  end

  defp check_reuse(password, %{previous_passwords: list}) do
    if password in list, do: {:violation, :reused_password}, else: :ok
  end

  defp check_username_similarity(password, %{
         username: username,
         max_username_similarity: threshold
       }) do
    dist = levenshtein(String.downcase(password), String.downcase(username))
    if dist > threshold, do: :ok, else: {:violation, :too_similar_to_username}
  end

  # ---------------------------------------------------------------------------
  # Levenshtein distance — iterative, two-row dynamic programming, O(m*n) time,
  # O(min(m,n)) space.
  # ---------------------------------------------------------------------------

  @doc false
  @spec levenshtein(String.t(), String.t()) :: non_neg_integer()
  def levenshtein(a, b) when is_binary(a) and is_binary(b) do
    # Work on grapheme clusters so that multi-byte Unicode is handled correctly.
    a_graphs = String.graphemes(a)
    b_graphs = String.graphemes(b)

    # Optimisation: ensure `b` is the shorter string (fewer columns = less memory).
    {a_graphs, b_graphs} =
      if length(a_graphs) < length(b_graphs),
        do: {b_graphs, a_graphs},
        else: {a_graphs, b_graphs}

    m = length(a_graphs)
    n = length(b_graphs)

    # Base case: one string is empty.
    cond do
      m == 0 -> n
      n == 0 -> m
      true -> do_levenshtein(a_graphs, b_graphs, m, n)
    end
  end

  defp do_levenshtein(a_graphs, b_graphs, _m, n) do
    # TODO
  end
end
```