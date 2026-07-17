# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule PasswordPolicy do
  @moduledoc """
  Scores password strength on a 0–100 scale and accepts or rejects based on a
  configurable threshold plus a set of hard rules.

  ## Usage

      PasswordPolicy.evaluate("Tr0ub4dor&3", %{username: "alice"})
      # => {:accepted, 62}

      PasswordPolicy.evaluate("abc", %{username: "operator"})
      # => {:rejected, 16, [:too_short, :insufficient_strength]}
  """

  @default_min_length 8
  @default_min_score 60
  @default_common_passwords []
  @default_max_username_similarity 3

  @spec evaluate(String.t(), map()) ::
          {:accepted, non_neg_integer()} | {:rejected, non_neg_integer(), [atom()]}
  def evaluate(password, %{username: _} = context) do
    cfg = build_config(context)
    score = strength_score(password)

    reasons =
      [
        min_length_reason(password, cfg),
        common_reason(password, cfg),
        similarity_reason(password, cfg),
        strength_reason(score, cfg)
      ]
      |> Enum.reject(&is_nil/1)

    case reasons do
      [] -> {:accepted, score}
      list -> {:rejected, score, list}
    end
  end

  def evaluate(_password, _context) do
    raise ArgumentError, "context map must include the :username key"
  end

  # ---------------------------------------------------------------------------
  # Config
  # ---------------------------------------------------------------------------

  defp build_config(context) do
    %{
      username: Map.fetch!(context, :username),
      min_length: Map.get(context, :min_length, @default_min_length),
      min_score: Map.get(context, :min_score, @default_min_score),
      common_passwords: Map.get(context, :common_passwords, @default_common_passwords),
      max_username_similarity:
        Map.get(context, :max_username_similarity, @default_max_username_similarity)
    }
  end

  # ---------------------------------------------------------------------------
  # Strength scoring
  # ---------------------------------------------------------------------------

  defp strength_score(password) do
    len = String.length(password)
    length_points = min(len, 20) * 2
    class_points = character_classes(password) * 10
    long_bonus = if len >= 16, do: 20, else: 0
    min(length_points + class_points + long_bonus, 100)
  end

  defp character_classes(password) do
    [~r/[A-Z]/, ~r/[a-z]/, ~r/[0-9]/, ~r/[^a-zA-Z0-9]/]
    |> Enum.count(fn re -> String.match?(password, re) end)
  end

  # ---------------------------------------------------------------------------
  # Rejection reasons (each returns an atom or nil)
  # ---------------------------------------------------------------------------

  defp min_length_reason(password, %{min_length: min}) do
    if String.length(password) < min, do: :too_short, else: nil
  end

  defp common_reason(password, %{common_passwords: list}) do
    lower = String.downcase(password)
    if Enum.any?(list, fn p -> String.downcase(p) == lower end), do: :common_password, else: nil
  end

  defp similarity_reason(password, %{username: username, max_username_similarity: threshold}) do
    dist = levenshtein(String.downcase(password), String.downcase(username))
    if dist <= threshold, do: :too_similar_to_username, else: nil
  end

  defp strength_reason(score, %{min_score: min}) do
    if score < min, do: :insufficient_strength, else: nil
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
defmodule PasswordPolicyV1Test do
  use ExUnit.Case, async: false

  # Exercises the weighted strength-score variant of PasswordPolicy.evaluate/2.
  # Scores are computed by hand from the deterministic formula in the prompt:
  #   length_points = min(len, 20) * 2
  #   class_points  = (# of {upper, lower, digit, special} present) * 10
  #   long_bonus    = if len >= 16, do: 20, else: 0
  #   score         = min(length_points + class_points + long_bonus, 100)

  test "accepts a moderately strong password at the default threshold" do
    # "Tr0ub4dor&3": len 11 -> 22, all 4 classes -> 40, no bonus -> score 62 (>= 60).
    assert PasswordPolicy.evaluate("Tr0ub4dor&3", %{username: "alice"}) == {:accepted, 62}
  end

  test "rejects a short weak password with all applicable reasons" do
    # "abc": len 3 -> 6, lowercase only -> 10, score 16. too_short and insufficient_strength.
    assert PasswordPolicy.evaluate("abc", %{username: "operator"}) ==
             {:rejected, 16, [:too_short, :insufficient_strength]}
  end

  test "rejects a common password even when it scores at the threshold" do
    # "Password1!": len 10 -> 20, all 4 classes -> 40, score 60 (meets threshold),
    # but it is on the common list -> case-insensitive rejection.
    result =
      PasswordPolicy.evaluate("Password1!", %{
        username: "operator",
        common_passwords: ["password1!"]
      })

    assert result == {:rejected, 60, [:common_password]}
  end

  test "rejects a strong password that is too similar to the username" do
    # Differs from the username by one character -> Levenshtein distance 1 (<= 3).
    result =
      PasswordPolicy.evaluate("Zx9#mQpLwT7$vBn3", %{username: "Zx9#mQpLwT7$vBn2"})

    assert result == {:rejected, 92, [:too_similar_to_username]}
  end

  test "honors a custom higher min_score" do
    # TODO
  end

  test "accepts a long, diverse password and reports the capped-range score" do
    # len 16 -> 32, all 4 classes -> 40, +20 bonus -> score 92.
    assert PasswordPolicy.evaluate("Zx9#mQpLwT7$vBn2", %{username: "operator"}) ==
             {:accepted, 92}
  end

  test "collects multiple rejection reasons in canonical order" do
    # "abc" is short (too_short), on the common list (common_password), and weak
    # (insufficient_strength). Order must be too_short, common_password, insufficient_strength.
    result =
      PasswordPolicy.evaluate("abc", %{username: "operator", common_passwords: ["abc"]})

    assert result == {:rejected, 16, [:too_short, :common_password, :insufficient_strength]}
  end

  test "raises when the context is missing the username" do
    assert_raise ArgumentError, fn -> PasswordPolicy.evaluate("whatever", %{min_score: 10}) end
  end

  # --- numeric boundaries and the Levenshtein distance contract ------------------------

  test "default min_length of 8 accepts an 8-character password but rejects a 7-character one" do
    # "Ab3#efgh": len 8 -> 16, all 4 classes -> 40, score 56. Length 8 is NOT below the
    # default hard minimum of 8, so :too_short must be absent (only the score fails).
    assert PasswordPolicy.evaluate("Ab3#efgh", %{username: "operator"}) ==
             {:rejected, 56, [:insufficient_strength]}

    # "Ab3#efg": len 7 -> 14, all 4 classes -> 40, score 54. Length 7 IS below 8 -> :too_short.
    assert PasswordPolicy.evaluate("Ab3#efg", %{username: "operator"}) ==
             {:rejected, 54, [:too_short, :insufficient_strength]}
  end

  test "accepts a password whose score exactly meets the default min_score of 60" do
    # "Xk7#mQpLwT": len 10 -> 20, all 4 classes -> 40, no bonus -> score 60.
    # 60 is not strictly below the default minimum of 60, so it must be accepted.
    assert PasswordPolicy.evaluate("Xk7#mQpLwT", %{username: "operator"}) == {:accepted, 60}
  end

  test "the +20 length bonus requires at least 16 characters, not 15" do
    # "Zx9#mQpLwT7$vBn": len 15 -> 30, all 4 classes -> 40, NO bonus -> score 70.
    assert PasswordPolicy.evaluate("Zx9#mQpLwT7$vBn", %{username: "operator"}) ==
             {:accepted, 70}
  end

  test "length points count at most 20 characters" do
    # 21 lowercase letters: length points capped at min(21, 20) * 2 = 40, lowercase class
    # only -> 10, len >= 16 -> +20. Score 70 exactly (not 68, not 72).
    assert PasswordPolicy.evaluate("abcdefghijklmnopqrstu", %{username: "operator"}) ==
             {:accepted, 70}
  end

  test "rejects when the username distance exactly equals max_username_similarity" do
    # Password and username differ in their last 3 characters -> Levenshtein distance 3,
    # which is <= the default max_username_similarity of 3 -> rejection.
    # len 16 -> 32, all 4 classes -> 40, +20 bonus -> score 92.
    assert PasswordPolicy.evaluate("Zx9#mQpLwT7$vXYZ", %{username: "Zx9#mQpLwT7$vBn2"}) ==
             {:rejected, 92, [:too_similar_to_username]}
  end

  test "Levenshtein distance is exact for multi-edit pairs" do
    # "kitten" -> "sitting" costs exactly 3 edits: not <= 2, but <= 3.
    refute too_similar?("sitting", "kitten", 2)
    assert too_similar?("sitting", "kitten", 3)

    # One extra leading character is exactly one deletion: not <= 0, but <= 1.
    refute too_similar?("xabc", "abc", 0)
    assert too_similar?("xabc", "abc", 1)
  end

  test "Levenshtein distance is exact for equal and single-character operands" do
    # Identical (case-insensitively equal) strings are distance 0.
    assert too_similar?("a", "a", 0)
    assert too_similar?("Zx9#mQpLwT7$vBn2", "zx9#mqplwt7$vbn2", 0)

    # "abc" vs "a" is exactly two deletions: not <= 1, but <= 2.
    refute too_similar?("abc", "a", 1)
    assert too_similar?("abc", "a", 2)
  end

  # Isolates the username-similarity rule: the hard length rule and the score rule are
  # configured so they can never fire, leaving :too_similar_to_username as the only
  # possible rejection reason.
  defp too_similar?(password, username, threshold) do
    context = %{
      username: username,
      max_username_similarity: threshold,
      min_length: 1,
      min_score: 0
    }

    case PasswordPolicy.evaluate(password, context) do
      {:accepted, _score} -> false
      {:rejected, _score, reasons} -> :too_similar_to_username in reasons
    end
  end

  test "lists all four rejection reasons together in canonical order" do
    # "abc": len 3 -> 6, lowercase only -> 10, score 16.
    # Short (< default 8), on the common list (matched case-insensitively against "ABC"),
    # Levenshtein distance 1 from "abd" (<= default 3), and score 16 < default 60.
    result =
      PasswordPolicy.evaluate("abc", %{
        username: "abd",
        common_passwords: ["ABC"]
      })

    assert result ==
             {:rejected, 16,
              [:too_short, :common_password, :too_similar_to_username, :insufficient_strength]}
  end

  test "a custom min_length rejects a password that clears the score threshold" do
    # len 16 -> 32, all 4 classes -> 40, +20 bonus -> score 92, which is well above the
    # default min_score of 60. The hard length rule must still fire, and it must be the
    # only reason reported.
    result =
      PasswordPolicy.evaluate("Zx9#mQpLwT7$vBn2", %{username: "operator", min_length: 20})

    assert result == {:rejected, 92, [:too_short]}
  end

  test "accepts a password whose username distance is 4 under the default similarity limit" do
    # "zx9#mqplwt7$wxyz" vs "zx9#mqplwt7$vbn2" differ in exactly the last 4 characters ->
    # Levenshtein distance 4, which is strictly greater than the default limit of 3.
    # len 16 -> 32, all 4 classes -> 40, +20 bonus -> score 92.
    assert PasswordPolicy.evaluate("Zx9#mQpLwT7$WXYZ", %{username: "Zx9#mQpLwT7$vBn2"}) ==
             {:accepted, 92}
  end

  test "each character class contributes exactly 10 points on its own" do
    # Each password is 4 characters -> 4 * 2 = 8 length points, no bonus, and is far
    # from the username, so the score isolates the character-class contribution.
    ctx = %{username: "operator"}

    # uppercase only -> 8 + 10 = 18
    assert PasswordPolicy.evaluate("ABCD", ctx) ==
             {:rejected, 18, [:too_short, :insufficient_strength]}

    # lowercase only -> 8 + 10 = 18
    assert PasswordPolicy.evaluate("abcd", ctx) ==
             {:rejected, 18, [:too_short, :insufficient_strength]}

    # digits only -> 8 + 10 = 18
    assert PasswordPolicy.evaluate("1234", ctx) ==
             {:rejected, 18, [:too_short, :insufficient_strength]}

    # specials only -> 8 + 10 = 18
    assert PasswordPolicy.evaluate("#$%^", ctx) ==
             {:rejected, 18, [:too_short, :insufficient_strength]}

    # all four classes at the same length -> 8 + 40 = 48
    assert PasswordPolicy.evaluate("Ab3#", ctx) ==
             {:rejected, 48, [:too_short, :insufficient_strength]}
  end
end
```
