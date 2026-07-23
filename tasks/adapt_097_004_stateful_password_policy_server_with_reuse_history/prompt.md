# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

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

## New specification

# Specification: `PasswordPolicy` — A Stateful Password Policy Server with Reuse History

## Overview

This document specifies an Elixir module called `PasswordPolicy`, implemented as a **GenServer**, that enforces a password policy *and* remembers each user's recent passwords so it can reject reuse across changes over time.

The server is configured once at startup and then services password-change requests for many users, keeping a bounded per-user history of previously accepted passwords.

Per-user histories must be independent.

## API

The module exposes the following public functions.

### `PasswordPolicy.start_link(opts)`

Starts the server. `opts` is a keyword list carrying the policy configuration and:

- `:name` (optional) — if given, registers the server under that name.
- `:history_size` (optional, default `5`) — how many of each user's most recently accepted passwords to remember and forbid reusing.
- Policy keys (all optional, same defaults as below): `:min_length` (`8`), `:max_length` (`128`), `:require_uppercase` (`true`), `:require_lowercase` (`true`), `:require_digit` (`true`), `:require_special` (`true`), `:common_passwords` (`[]`), `:max_username_similarity` (`3`).

### `PasswordPolicy.set_password(server, username, password)`

Validates `password` for `username` against the policy and against that user's remembered history. Returns `:ok` when it passes every rule (and, as a side effect, records the password at the front of the user's history, evicting the oldest beyond `:history_size`). Returns `{:error, violations}` — a list of every failing rule atom — otherwise, and in that case the history is **not** modified.

### `PasswordPolicy.history_count(server, username)`

Returns the number of passwords currently remembered for `username` (`0` if the user is unknown).

## Validation rules

Each rule below is paired with the violation atom it produces.

- `:too_short` / `:too_long` — length outside `[min_length, max_length]`.
- `:no_uppercase`, `:no_lowercase`, `:no_digit`, `:no_special` — the corresponding required character class is missing (a "special" character is any non-alphanumeric character). The check is skipped when its `:require_*` option is `false`.
- `:common_password` — the password matches any entry in `:common_passwords` (case-insensitive).
- `:reused_password` — the password exactly matches any password currently in that user's remembered history.
- `:too_similar_to_username` — the password's Levenshtein distance from the username (compared case-insensitively) is less than or equal to `:max_username_similarity`.

## Edge cases and reporting order

All violations are reported, in this canonical order: `:too_short`, `:too_long`, `:no_uppercase`, `:no_lowercase`, `:no_digit`, `:no_special`, `:common_password`, `:reused_password`, `:too_similar_to_username`.

## Implementation constraints

Levenshtein distance must be implemented by hand using dynamic programming — no external library may be used for it. All other logic must likewise use only the Elixir/OTP standard library with no external dependencies.

## Deliverable

The complete module, in a single file.
