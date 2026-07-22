Implement the private `do_levenshtein/3` function. It is the inner engine of the
Levenshtein distance calculation and is only ever called with the two grapheme
lists already non-empty (both empty-string cases are handled by the caller).

It receives `a_graphs` (the longer grapheme list), `b_graphs` (the shorter
grapheme list), and `n` (the length of `b_graphs`). Using an iterative two-row
dynamic-programming approach, it must:

- Seed the "previous" row with the base cases `0..n` (the cost of turning an empty
  prefix of `a` into each prefix of `b`), stored as a tuple for O(1) indexed
  access.
- Iterate over each grapheme of `a_graphs` together with its 1-based index `i`,
  folding over the rows so that each iteration produces the next DP row from the
  previous one.
- For each row, iterate over each grapheme of `b_graphs` with its 1-based index
  `j`, tracking the current row being built and the value immediately to the
  `left`. The first cell of every new row starts at `i` (the cost of deleting `i`
  characters). For cell `j`, read the diagonal (`prev_row[j-1]`) and the cell
  above (`prev_row[j]`), set `cost` to `0` when the two graphemes are equal and
  `1` otherwise, and take the minimum of `left + 1` (insertion), `up + 1`
  (deletion), and `diag + cost` (substitution).
- Build each new row in order (reverse the accumulator, since cells are prepended)
  and convert it to a tuple for the next fold step.
- After processing every grapheme of `a_graphs`, return the last element (index
  `n`) of the final row — the full Levenshtein distance.

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
    # TODO
  end
end
```