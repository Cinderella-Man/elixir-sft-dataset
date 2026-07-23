# One bug. Find it. Fix it.

The module below implements the task that follows, except for a single
behavior bug. The bottom of this prompt shows the real failure report from
its (hidden) test suite. Deliver the full corrected module: smallest
possible change, no restructuring, nothing else touched.

## Target behavior

I'm picking up the account-settings work and I need a password checker I can drop in, so could you write me a module called `PasswordPolicy` that validates passwords against a configurable set of rules? Keep the surface small — one public function, `PasswordPolicy.validate(password, context)`. It should hand back `:ok` when the password passes all the active rules, and `{:error, violations}` otherwise, where `violations` is a list of atoms naming every rule that failed. That last part matters to me: I want all of the violations reported, not just the first one we trip over, because the UI shows them together.

The `context` argument is a map, and it's doing double duty — it carries both the configuration and the per-user data. Here's what I need it to support. `:username` is required; it's the username the password is being set for. `:min_length` is optional and defaults to `8` — the minimum number of characters. `:max_length` is optional, defaults to `128`. `:require_uppercase` is optional, defaults to `true`, and means the password must contain at least one uppercase ASCII letter. `:require_lowercase` is the same shape, optional, default `true`, at least one lowercase ASCII letter. `:require_digit`, optional, default `true`, at least one digit. `:require_special`, optional, default `true`, meaning at least one character that is not alphanumeric.

Then two list-shaped ones. `:common_passwords` is optional and defaults to `[]`; it's a list of plaintext strings we consider too common, and the password must not appear in that list — compare case-insensitively there. `:previous_passwords` is also optional with default `[]`; it's a list of previously used plaintext passwords, and the new password must not match any of them exactly.

Last one is the fiddly one: `:max_username_similarity`, optional, default `3`. Reject the password if its Levenshtein distance from the username is less than or equal to that value — i.e. the distance has to be strictly greater than the threshold to pass. Compute the distance on the literal password and username, case-sensitively, with no case folding applied to either side.

For the atoms themselves, please use exactly these: `:too_short`, `:too_long`, `:no_uppercase`, `:no_lowercase`, `:no_digit`, `:no_special`, `:common_password`, `:reused_password`, `:too_similar_to_username`.

One implementation constraint — write the Levenshtein distance yourself with dynamic programming, don't pull in an external library for it. Same goes for everything else in there: Elixir/OTP standard library only, no external dependencies.

Send it over as the complete module in a single file.

## The buggy module

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
      [] -> :error
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

## Failing test report

```
8 of 25 test(s) failed:

  * test reuse comparison is exact, so a case variant of a previous password passes
      
      
      Assertion with == failed
      code:  assert case_variant == :ok
      left:  :error
      right: :ok
      

  * test valid password - all rules pass
      
      
      Assertion with == failed
      code:  assert result == :ok
      left:  :error
      right: :ok
      

  * test valid password - username similarity just outside threshold
      
      
      Assertion with == failed
      code:  assert result == :ok
      left:  :error
      right: :ok
      

  * test valid with no optional rules enabled
      
      
      Assertion with == failed
      code:  assert result == :ok
      left:  :error
      right: :ok
      

  (…4 more)
```
