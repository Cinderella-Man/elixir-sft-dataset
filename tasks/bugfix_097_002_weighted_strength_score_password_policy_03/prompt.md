# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

Write me an Elixir module called `PasswordPolicy` that scores password *strength* on a 0–100 scale and accepts or rejects based on a configurable threshold, rather than treating every rule as an equal pass/fail gate.

I need a single public function:
- `PasswordPolicy.evaluate(password, context)` which returns `{:accepted, score}` when the password clears every hard rule **and** its strength score meets the minimum, or `{:rejected, score, reasons}` where `reasons` is a list of atoms describing every reason the password was rejected (report all of them, not just the first). `score` is always the computed integer strength score, present in both the accepted and rejected results.

The `context` argument is a map that drives configuration and per-user data:
- `:username` (required) — the username the password is being set for. If the context map does not include `:username`, `evaluate/2` must raise an `ArgumentError`.
- `:min_length` (optional, default `8`) — a *hard* minimum; shorter passwords are rejected with `:too_short` regardless of score.
- `:min_score` (optional, default `60`) — the minimum strength score required; passwords scoring strictly below this are rejected with `:insufficient_strength`.
- `:common_passwords` (optional, default `[]`) — a list of plaintext strings considered too common; a case-insensitive match is a hard rejection with `:common_password`.
- `:max_username_similarity` (optional, default `3`) — the password is rejected with `:too_similar_to_username` if its Levenshtein distance from the username (compared case-insensitively) is less than or equal to this value.

The strength score is computed deterministically as the sum (capped at `100`) of:
- **Length points:** `2` points per character, counting at most `20` characters (so `0`–`40`).
- **Character-class points:** `10` points for each of the following classes present at least once — uppercase ASCII letter, lowercase ASCII letter, digit, and non-alphanumeric ("special") character (so `0`–`40`).
- **Length bonus:** a flat `20` points if the password is at least `16` characters long.

The rejection atoms to use are: `:too_short`, `:common_password`, `:too_similar_to_username`, `:insufficient_strength`. When multiple apply, list them in that canonical order.

Implement Levenshtein distance yourself using dynamic programming — do not use any external library. All other logic must also use only the Elixir/OTP standard library with no external dependencies.

Give me the complete module in a single file.

## The buggy module

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
  @default_min_score 61
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

## Failing test report

```
1 of 8 test(s) failed:

  * test rejects a common password even when it scores at the threshold
      
      
      Assertion with == failed
      code:  assert result == {:rejected, 60, [:common_password]}
      left:  {:rejected, 60, [:common_password, :insufficient_strength]}
      right: {:rejected, 60, [:common_password]}
```
