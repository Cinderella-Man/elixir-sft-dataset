# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `check_lowercase` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir module called `PasswordPolicy` that validates passwords against a configurable set of rules.

I need a single public function:
- `PasswordPolicy.validate(password, context)` which returns `:ok` if the password passes all active rules, or `{:error, violations}` where `violations` is a list of atoms describing every rule that failed (all violations must be reported, not just the first one).

The `context` argument is a map that drives both configuration and per-user data. It supports the following keys:
- `:username` (required) — the username the password is being set for.
- `:min_length` (optional, default `8`) — minimum number of characters.
- `:max_length` (optional, default `128`) — maximum number of characters.
- `:require_uppercase` (optional, default `true`) — must contain at least one uppercase ASCII letter.
- `:require_lowercase` (optional, default `true`) — must contain at least one lowercase ASCII letter.
- `:require_digit` (optional, default `true`) — must contain at least one digit.
- `:require_special` (optional, default `true`) — must contain at least one character that is not alphanumeric.
- `:common_passwords` (optional, default `[]`) — a list of plaintext strings considered too common; the password must not appear in this list (case-insensitive comparison).
- `:previous_passwords` (optional, default `[]`) — a list of previously used plaintext passwords; the new password must not match any of them exactly.
- `:max_username_similarity` (optional, default `3`) — the password is rejected if its Levenshtein distance from the username is less than or equal to this value (i.e. distance must be strictly greater than this threshold). The distance is computed on the literal password and username, case-sensitively, with no case folding applied to either side.

The violation atoms to use are: `:too_short`, `:too_long`, `:no_uppercase`, `:no_lowercase`, `:no_digit`, `:no_special`, `:common_password`, `:reused_password`, `:too_similar_to_username`.

Implement Levenshtein distance yourself using dynamic programming — do not use any external library. All other logic must also use only the Elixir/OTP standard library with no external dependencies.

Give me the complete module in a single file.

## The module with `check_lowercase` missing

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
      # => {:error, [:too_short, :no_uppercase, :no_digit, :no_special,
      #               :too_similar_to_username]}
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

  defp check_lowercase(_password, %{require_lowercase: false}) do
    # TODO
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

  defp check_username_similarity(
         password,
         %{username: username, max_username_similarity: threshold}
       ) do
    # The spec calls for the literal Levenshtein distance between the password and
    # the username: no case folding is applied to either side.
    dist = levenshtein(password, username)
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
    # `prev` holds the distances for the previous row (i-1).
    # Initialise for i = 0: distance from "" to b[0..j] = j.
    prev = Enum.to_list(0..n) |> List.to_tuple()

    a_graphs
    |> Enum.with_index(1)
    |> Enum.reduce(prev, fn {a_char, i}, prev_row ->
      # curr[0] = i  (distance from a[0..i] to "")
      curr_row =
        b_graphs
        |> Enum.with_index(1)
        |> Enum.reduce({[i], i}, fn {b_char, j}, {acc, left} ->
          # prev[j-1]
          diag = elem(prev_row, j - 1)
          # prev[j]
          up = elem(prev_row, j)

          cost = if a_char == b_char, do: 0, else: 1

          val =
            Enum.min([
              # deletion
              left + 1,
              # insertion
              up + 1,
              # substitution (or match)
              diag + cost
            ])

          {[val | acc], val}
        end)
        |> elem(0)
        |> Enum.reverse()
        |> List.to_tuple()

      curr_row
    end)
    # bottom-right cell = final distance
    |> elem(n)
  end
end
```

Give me only the complete implementation of `check_lowercase` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
