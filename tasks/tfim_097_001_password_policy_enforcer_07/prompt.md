# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule PasswordPolicyEnforcerTest do
  use ExUnit.Case, async: true

  # ExUnit port of the original hand-rolled harness for `PasswordPolicy`.
  #
  # Each original `test(name, ...)` case is mapped 1:1 to an ExUnit `test`, using
  # the same inputs to `PasswordPolicy.validate/2`. Multi-violation `{:error, [..]}`
  # results are compared order-independently (sorted / MapSet) so violation order
  # does not matter, matching the original MapSet.subset?/equal? semantics.
  #
  # Three of the original *expected* values were incorrect (the original harness was
  # never actually invoked, so they were never validated). They are corrected here to
  # the solution's true, spec-conformant behaviour, with the test PURPOSE preserved:
  #   * "common password is case-insensitive" — "PASSWORD1!" has no lowercase and
  #     require_lowercase defaults to true, so :no_lowercase legitimately fires too.
  #   * "too similar to username - distance <= threshold" — Levenshtein("user1234!",
  #     "user") = 5; the original threshold of 3 never triggered rejection. Corrected
  #     to 5 so distance <= threshold actually holds (boundary case).
  #   * "password identical to username is rejected" — "carol" is 5 chars and
  #     min_length defaults to 8, so :too_short legitimately fires alongside similarity.

  defp violations(result) do
    assert {:error, errs} = result
    errs
  end

  # --- Single-rule failures ---

  test "too short" do
    result = PasswordPolicy.validate("Ab1!", %{username: "user", min_length: 8})
    assert Enum.sort(violations(result)) == Enum.sort([:too_short])
  end

  test "too long" do
    result =
      PasswordPolicy.validate("Ab1!" <> String.duplicate("x", 200), %{
        username: "user",
        max_length: 20
      })

    assert Enum.sort(violations(result)) == Enum.sort([:too_long])
  end

  test "no uppercase" do
    result = PasswordPolicy.validate("abc123!!", %{username: "user", require_uppercase: true})
    assert Enum.sort(violations(result)) == Enum.sort([:no_uppercase])
  end

  test "no lowercase" do
    result = PasswordPolicy.validate("ABC123!!", %{username: "user", require_lowercase: true})
    assert Enum.sort(violations(result)) == Enum.sort([:no_lowercase])
  end

  test "no digit" do
    result = PasswordPolicy.validate("Abcdefg!", %{username: "user", require_digit: true})
    assert Enum.sort(violations(result)) == Enum.sort([:no_digit])
  end

  test "no special character" do
    # TODO
  end

  test "common password" do
    result =
      PasswordPolicy.validate("Password1!", %{
        username: "user",
        common_passwords: ["password1!", "letmein"]
      })

    assert Enum.sort(violations(result)) == Enum.sort([:common_password])
  end

  test "common password is case-insensitive" do
    # "PASSWORD1!" matches the common list case-insensitively AND has no lowercase
    # letter (require_lowercase defaults to true), so both violations fire.
    result =
      PasswordPolicy.validate("PASSWORD1!", %{
        username: "user",
        common_passwords: ["password1!"]
      })

    assert Enum.sort(violations(result)) == Enum.sort([:common_password, :no_lowercase])
  end

  test "reused password" do
    result =
      PasswordPolicy.validate("Correct1!", %{
        username: "user",
        previous_passwords: ["OldPass9#", "Correct1!"]
      })

    assert Enum.sort(violations(result)) == Enum.sort([:reused_password])
  end

  test "too similar to username - distance <= threshold" do
    # Levenshtein("user1234!", "user") == 5, so the threshold must be >= 5 for the
    # similarity rule to reject (boundary: distance == threshold).
    result =
      PasswordPolicy.validate("user1234!", %{
        username: "user",
        require_uppercase: false,
        max_username_similarity: 5
      })

    assert Enum.sort(violations(result)) == Enum.sort([:too_similar_to_username])
  end

  # --- Multiple simultaneous failures ---

  test "multiple violations: too short + no uppercase + no digit" do
    result =
      PasswordPolicy.validate("abc!", %{
        username: "other",
        min_length: 8,
        require_uppercase: true,
        require_digit: true,
        require_lowercase: true,
        require_special: true
      })

    expected = MapSet.new([:too_short, :no_uppercase, :no_digit])
    got = MapSet.new(violations(result))
    assert MapSet.subset?(expected, got)
  end

  test "multiple violations: common + reused" do
    result =
      PasswordPolicy.validate("Letmein1!", %{
        username: "other",
        require_uppercase: false,
        require_digit: false,
        require_special: false,
        require_lowercase: false,
        common_passwords: ["letmein1!"],
        previous_passwords: ["Letmein1!"]
      })

    assert Enum.sort(violations(result)) == Enum.sort([:common_password, :reused_password])
  end

  # --- Passing cases ---

  test "valid password - all rules pass" do
    result =
      PasswordPolicy.validate("Tr0ub4dor&3", %{
        username: "alice",
        min_length: 8,
        max_length: 64,
        require_uppercase: true,
        require_lowercase: true,
        require_digit: true,
        require_special: true,
        common_passwords: ["password123"],
        previous_passwords: ["OldPass1!"]
      })

    assert result == :ok
  end

  test "valid password - username similarity just outside threshold" do
    result =
      PasswordPolicy.validate("userXYZW1!", %{
        username: "user",
        require_uppercase: true,
        require_lowercase: false,
        max_username_similarity: 3
      })

    assert result == :ok
  end

  test "valid with no optional rules enabled" do
    result =
      PasswordPolicy.validate("anything", %{
        username: "bob",
        min_length: 1,
        require_uppercase: false,
        require_lowercase: false,
        require_digit: false,
        require_special: false
      })

    assert result == :ok
  end

  # --- Levenshtein edge cases ---

  test "password identical to username is rejected" do
    # "carol" is 5 chars and min_length defaults to 8, so :too_short fires alongside
    # the similarity violation (distance 0 <= 3).
    result =
      PasswordPolicy.validate("carol", %{
        username: "carol",
        require_uppercase: false,
        require_lowercase: false,
        require_digit: false,
        require_special: false,
        max_username_similarity: 3
      })

    assert Enum.sort(violations(result)) == Enum.sort([:too_short, :too_similar_to_username])
  end

  test "password far from username is accepted" do
    result =
      PasswordPolicy.validate("Zx9#mQpL", %{
        username: "alice",
        max_username_similarity: 3
      })

    assert result == :ok
  end

  test "username similarity uses literal Levenshtein distance without case folding" do
    # Literal distance("ALICE1!x", "alice") == 8 (no character matches, lengths 8 vs 5),
    # which is strictly greater than the default threshold of 3, so the password passes.
    result = PasswordPolicy.validate("ALICE1!x", %{username: "alice"})

    assert result == :ok
  end

  test "max_length defaults to 128 when the option is omitted" do
    too_long = "Aa1!" <> String.duplicate("x", 125)
    assert {:error, errs} = PasswordPolicy.validate(too_long, %{username: "someuser"})
    assert Enum.sort(errs) == Enum.sort([:too_long])

    at_limit = "Aa1!" <> String.duplicate("x", 124)
    assert PasswordPolicy.validate(at_limit, %{username: "someuser"}) == :ok
  end

  test "max_username_similarity defaults to 3 when the option is omitted" do
    # distance("Xyz9!abc", "Xyz9!qrs") == 3, i.e. exactly at the default threshold.
    assert {:error, errs} = PasswordPolicy.validate("Xyz9!abc", %{username: "Xyz9!qrs"})
    assert Enum.sort(errs) == Enum.sort([:too_similar_to_username])

    # distance("Xyz9!abc", "Xyz9!qrst") == 4, strictly greater than the default threshold.
    assert PasswordPolicy.validate("Xyz9!abc", %{username: "Xyz9!qrst"}) == :ok
  end

  test "require_uppercase defaults to true when the option is omitted" do
    assert {:error, errs} = PasswordPolicy.validate("abcdefg1!", %{username: "zzzzzzzz"})
    assert Enum.sort(errs) == Enum.sort([:no_uppercase])
  end

  test "require_digit defaults to true when the option is omitted" do
    assert {:error, errs} = PasswordPolicy.validate("Abcdefg!", %{username: "zzzzzzzz"})
    assert Enum.sort(errs) == Enum.sort([:no_digit])
  end

  test "require_special defaults to true when the option is omitted" do
    assert {:error, errs} = PasswordPolicy.validate("Abcdef12", %{username: "zzzzzzzz"})
    assert Enum.sort(errs) == Enum.sort([:no_special])
  end
end
```
