# Rework this solution for a changed brief

The module below is a complete, tested solution to a neighboring task. Treat
it as your starting codebase, not as a suggestion — carry over what still
fits and rewrite what the new brief demands. Where old code and the new
specification conflict (module name, public API, behavior, constraints,
output format), the new specification is authoritative. Return the complete
final result.

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

I need a password auditing module and I'd rather describe it to you than write it myself. Call it `PasswordPolicy`. The idea is that it audits a password and classifies each failing rule by severity, so we can distinguish blocking **errors** from non-blocking **warnings**.

There's just one public function I want: `PasswordPolicy.audit(password, context)`. It returns a report map shaped like `%{status: :ok | :error, errors: [atom()], warnings: [atom()]}`. The `errors` key lists every blocking violation, `warnings` lists every advisory violation, and `status` comes out as `:error` when there's at least one error and `:ok` otherwise — warnings on their own never flip the status to `:error`. Important: report all violations, not just the first one you hit.

The rules split into two severities. The blocking errors are minimum length (`:too_short`), maximum length (`:too_long`), the common-password blocklist (`:common_password`), and reuse of a previously-used password (`:reused_password`). The advisory warnings are missing uppercase (`:no_uppercase`), missing lowercase (`:no_lowercase`), missing digit (`:no_digit`), missing special character (`:no_special`), and being too similar to the username (`:too_similar_to_username`).

The `context` argument is a map that carries both the configuration and the per-user data. `:username` is required — it's the username the password is being set for — and if `context` doesn't contain a `:username` key, I want you to raise `ArgumentError`. Everything else is optional with a default: `:min_length` (default `8`) is the minimum number of characters; `:max_length` (default `128`) is the maximum; `:require_uppercase` (default `true`) means the password must contain at least one uppercase ASCII letter; `:require_lowercase` (default `true`) means at least one lowercase ASCII letter; `:require_digit` (default `true`) means at least one digit; `:require_special` (default `true`) means at least one non-alphanumeric character; `:common_passwords` (default `[]`) is a list of plaintext strings considered too common, and the password must not match any of them, compared case-insensitively; `:previous_passwords` (default `[]`) is a list of previously used plaintext passwords, and the new password must not match any of them exactly; `:max_username_similarity` (default `3`) means the password triggers the similarity warning if its Levenshtein distance from the username — compared case-insensitively — is less than or equal to that value; and `:strict` (default `false`), which when set to `true` *promotes* every warning to an error: the `warnings` list comes back empty, all violations show up in `errors`, and any violation at all forces `status: :error`.

One more thing on output: both `errors` and `warnings` have to be listed in this canonical rule order — `:too_short`, `:too_long`, `:no_uppercase`, `:no_lowercase`, `:no_digit`, `:no_special`, `:common_password`, `:reused_password`, `:too_similar_to_username`.

Please implement Levenshtein distance yourself with dynamic programming — no external library for it. Same goes for the rest of the logic: Elixir/OTP standard library only, no external dependencies.

Send me back the complete module in a single file.
