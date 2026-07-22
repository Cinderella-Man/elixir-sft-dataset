defmodule PasswordPolicy do
  @moduledoc """
  Score-based password policy evaluation.

  Instead of treating every rule as an equal pass/fail gate, `PasswordPolicy` computes a
  deterministic strength score on a `0`–`100` scale and combines it with a small set of hard
  rules (minimum length, common-password blocklist, similarity to the username).

  A password is accepted only when it clears every hard rule *and* its score meets the
  configured minimum. When it does not, every applicable reason is reported.

  ## Scoring

  The score is the sum of the following components, capped at `100`:

    * **Length points** — `2` points per character, counting at most `20` characters (`0`–`40`).
    * **Character-class points** — `10` points for each class present at least once: uppercase
      ASCII letter, lowercase ASCII letter, digit, and non-alphanumeric "special" character
      (`0`–`40`).
    * **Length bonus** — a flat `20` points when the password is at least `16` characters long.

  ## Configuration

  Configuration and per-user data are supplied through the `context` map:

    * `:username` (required) — the username the password is being set for.
    * `:min_length` (default `8`) — hard minimum length.
    * `:min_score` (default `60`) — minimum strength score required.
    * `:common_passwords` (default `[]`) — plaintext strings matched case-insensitively.
    * `:max_username_similarity` (default `3`) — maximum allowed Levenshtein distance (exclusive)
      between the password and the username, compared case-insensitively.

  ## Examples

      iex> PasswordPolicy.evaluate("Tr0ub4dor&3xtra", %{username: "alice"})
      {:accepted, 90}

      iex> PasswordPolicy.evaluate("abc", %{username: "alice"})
      {:rejected, 26, [:too_short, :insufficient_strength]}

  """

  @type reason ::
          :too_short
          | :common_password
          | :too_similar_to_username
          | :insufficient_strength

  @type context :: %{
          required(:username) => String.t(),
          optional(:min_length) => non_neg_integer(),
          optional(:min_score) => integer(),
          optional(:common_passwords) => [String.t()],
          optional(:max_username_similarity) => non_neg_integer()
        }

  @type result :: {:accepted, non_neg_integer()} | {:rejected, non_neg_integer(), [reason()]}

  @default_min_length 8
  @default_min_score 60
  @default_common_passwords []
  @default_max_username_similarity 3

  @max_score 100
  @length_points_per_char 2
  @max_counted_chars 20
  @class_points 10
  @long_password_length 16
  @long_password_bonus 20

  # Canonical ordering for reported rejection reasons.
  @reason_order [
    :too_short,
    :common_password,
    :too_similar_to_username,
    :insufficient_strength
  ]

  @doc """
  Evaluates `password` against the policy described by `context`.

  Returns `{:accepted, score}` when the password satisfies every hard rule and its strength score
  is at least the configured `:min_score`. Otherwise returns `{:rejected, score, reasons}`, where
  `reasons` lists *every* applicable rejection atom in canonical order: `:too_short`,
  `:common_password`, `:too_similar_to_username`, `:insufficient_strength`.

  The `score` is always the computed strength score, in both the accepted and rejected results.

  Raises `ArgumentError` when `context` does not contain a `:username` key.

  ## Examples

      iex> PasswordPolicy.evaluate("C0rrect-Horse-Battery!", %{username: "alice"})
      {:accepted, 100}

      iex> PasswordPolicy.evaluate("password", %{username: "bob", common_passwords: ["PASSWORD"]})
      {:rejected, 26, [:common_password, :insufficient_strength]}

      iex> PasswordPolicy.evaluate("secret", %{})
      ** (ArgumentError) context must include a :username key

  """
  @spec evaluate(String.t(), context()) :: result()
  def evaluate(password, context) when is_binary(password) and is_map(context) do
    username = fetch_username!(context)

    min_length = Map.get(context, :min_length, @default_min_length)
    min_score = Map.get(context, :min_score, @default_min_score)
    common_passwords = Map.get(context, :common_passwords, @default_common_passwords)
    max_similarity = Map.get(context, :max_username_similarity, @default_max_username_similarity)

    score = score(password)

    reasons =
      []
      |> put_reason(:too_short, String.length(password) < min_length)
      |> put_reason(:common_password, common?(password, common_passwords))
      |> put_reason(
        :too_similar_to_username,
        similar_to_username?(password, username, max_similarity)
      )
      |> put_reason(:insufficient_strength, score < min_score)
      |> order_reasons()

    case reasons do
      [] -> {:accepted, score}
      reasons -> {:rejected, score, reasons}
    end
  end

  @doc """
  Computes the deterministic strength score of `password` on a `0`–`100` scale.

  The score is the sum of length points (`2` per character, at most `20` characters counted),
  character-class points (`10` each for uppercase, lowercase, digit and special characters) and a
  flat `20` point bonus for passwords of at least `16` characters, capped at `100`.

  ## Examples

      iex> PasswordPolicy.score("")
      0

      iex> PasswordPolicy.score("abcdefgh")
      26

      iex> PasswordPolicy.score("Abcdefgh1234567!")
      100

  """
  @spec score(String.t()) :: non_neg_integer()
  def score(password) when is_binary(password) do
    graphemes = String.graphemes(password)
    length = Kernel.length(graphemes)

    total =
      length_points(length) + class_points(graphemes) + length_bonus(length)

    min(total, @max_score)
  end

  @doc """
  Computes the Levenshtein edit distance between two strings.

  Uses an iterative dynamic-programming approach over a single row of the distance matrix, so it
  runs in `O(len(left) * len(right))` time and `O(min(len(left), len(right)))` space. Distances
  are measured in graphemes, and the comparison is case-sensitive; callers that need a
  case-insensitive distance should downcase their inputs first.

  ## Examples

      iex> PasswordPolicy.levenshtein("kitten", "sitting")
      3

      iex> PasswordPolicy.levenshtein("alice", "alice")
      0

      iex> PasswordPolicy.levenshtein("", "abc")
      3

  """
  @spec levenshtein(String.t(), String.t()) :: non_neg_integer()
  def levenshtein(left, right) when is_binary(left) and is_binary(right) do
    do_levenshtein(String.graphemes(left), String.graphemes(right))
  end

  # -- Hard rules -----------------------------------------------------------------------------

  @spec fetch_username!(map()) :: String.t()
  defp fetch_username!(context) do
    case Map.fetch(context, :username) do
      {:ok, username} when is_binary(username) ->
        username

      {:ok, other} ->
        raise ArgumentError, ":username must be a string, got: #{inspect(other)}"

      :error ->
        raise ArgumentError, "context must include a :username key"
    end
  end

  @spec common?(String.t(), [String.t()]) :: boolean()
  defp common?(password, common_passwords) do
    normalized = String.downcase(password)
    Enum.any?(common_passwords, fn common -> String.downcase(common) == normalized end)
  end

  @spec similar_to_username?(String.t(), String.t(), non_neg_integer()) :: boolean()
  defp similar_to_username?(password, username, max_similarity) do
    distance = levenshtein(String.downcase(password), String.downcase(username))
    distance <= max_similarity
  end

  # -- Scoring --------------------------------------------------------------------------------

  @spec length_points(non_neg_integer()) :: non_neg_integer()
  defp length_points(length) do
    min(length, @max_counted_chars) * @length_points_per_char
  end

  @spec length_bonus(non_neg_integer()) :: non_neg_integer()
  defp length_bonus(length) when length >= @long_password_length, do: @long_password_bonus
  defp length_bonus(_length), do: 0

  @spec class_points([String.t()]) :: non_neg_integer()
  defp class_points(graphemes) do
    graphemes
    |> Enum.reduce(MapSet.new(), fn grapheme, classes ->
      case classify(grapheme) do
        nil -> classes
        class -> MapSet.put(classes, class)
      end
    end)
    |> MapSet.size()
    |> Kernel.*(@class_points)
  end

  @spec classify(String.t()) :: :upper | :lower | :digit | :special | nil
  defp classify(<<char>>) when char >= ?A and char <= ?Z, do: :upper
  defp classify(<<char>>) when char >= ?a and char <= ?z, do: :lower
  defp classify(<<char>>) when char >= ?0 and char <= ?9, do: :digit
  defp classify(_grapheme), do: :special

  # -- Levenshtein distance -------------------------------------------------------------------

  @spec do_levenshtein([String.t()], [String.t()]) :: non_neg_integer()
  defp do_levenshtein(left, []), do: Kernel.length(left)
  defp do_levenshtein([], right), do: Kernel.length(right)

  defp do_levenshtein(left, right) do
    # Keep the shorter list as the row so the working row stays O(min(m, n)) in size.
    {row_chars, column_chars} =
      if Kernel.length(left) <= Kernel.length(right), do: {left, right}, else: {right, left}

    initial_row = Enum.to_list(0..Kernel.length(row_chars))

    column_chars
    |> Enum.with_index(1)
    |> Enum.reduce(initial_row, fn {column_char, row_index}, previous_row ->
      build_row(row_chars, column_char, row_index, previous_row)
    end)
    |> List.last()
  end

  @spec build_row([String.t()], String.t(), pos_integer(), [non_neg_integer()]) ::
          [non_neg_integer()]
  defp build_row(row_chars, column_char, row_index, previous_row) do
    [diagonal | rest_previous] = previous_row

    {reversed_row, _diagonal, _rest} =
      Enum.reduce(row_chars, {[row_index], diagonal, rest_previous}, fn
        row_char, {[left | _] = acc, diagonal, [above | rest]} ->
          substitution = if row_char == column_char, do: diagonal, else: diagonal + 1
          cost = Enum.min([above + 1, left + 1, substitution])
          {[cost | acc], above, rest}
      end)

    Enum.reverse(reversed_row)
  end

  # -- Reason collection ----------------------------------------------------------------------

  @spec put_reason([reason()], reason(), boolean()) :: [reason()]
  defp put_reason(reasons, reason, true), do: [reason | reasons]
  defp put_reason(reasons, _reason, false), do: reasons

  @spec order_reasons([reason()]) :: [reason()]
  defp order_reasons(reasons) do
    Enum.filter(@reason_order, fn reason -> reason in reasons end)
  end
end