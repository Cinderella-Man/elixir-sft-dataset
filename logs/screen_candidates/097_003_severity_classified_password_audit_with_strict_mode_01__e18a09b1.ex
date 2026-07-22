defmodule PasswordPolicy do
  @moduledoc """
  Audits a password against a set of configurable rules and classifies each failing rule by
  severity.

  Rules are split into two severities:

    * **errors** (blocking) — `:too_short`, `:too_long`, `:common_password`, `:reused_password`
    * **warnings** (advisory) — `:no_uppercase`, `:no_lowercase`, `:no_digit`, `:no_special`,
      `:too_similar_to_username`

  `audit/2` reports *every* violation (not just the first) and returns a report map of the
  shape `%{status: :ok | :error, errors: [atom()], warnings: [atom()]}`. The status is
  `:error` when at least one blocking violation is present, and `:ok` otherwise — advisory
  violations alone never make the status `:error`.

  When the context sets `strict: true`, every warning is promoted to an error: the `warnings`
  list is emptied, all violations are reported in `errors`, and any violation at all forces
  `status: :error`.

  Both lists are returned in a canonical rule order (see `audit/2`).

  ## Example

      iex> PasswordPolicy.audit("hunter2!", %{username: "alice"})
      %{status: :ok, errors: [], warnings: [:no_uppercase]}
  """

  @canonical_order [
    :too_short,
    :too_long,
    :no_uppercase,
    :no_lowercase,
    :no_digit,
    :no_special,
    :common_password,
    :reused_password,
    :too_similar_to_username
  ]

  @error_rules [:too_short, :too_long, :common_password, :reused_password]

  @default_min_length 8
  @default_max_length 128
  @default_max_username_similarity 3

  @type rule ::
          :too_short
          | :too_long
          | :no_uppercase
          | :no_lowercase
          | :no_digit
          | :no_special
          | :common_password
          | :reused_password
          | :too_similar_to_username

  @type context :: %{
          required(:username) => String.t(),
          optional(:min_length) => non_neg_integer(),
          optional(:max_length) => non_neg_integer(),
          optional(:require_uppercase) => boolean(),
          optional(:require_lowercase) => boolean(),
          optional(:require_digit) => boolean(),
          optional(:require_special) => boolean(),
          optional(:common_passwords) => [String.t()],
          optional(:previous_passwords) => [String.t()],
          optional(:max_username_similarity) => non_neg_integer(),
          optional(:strict) => boolean()
        }

  @type report :: %{status: :ok | :error, errors: [rule()], warnings: [rule()]}

  @doc """
  Audits `password` against the rules configured in `context`.

  ## Context keys

    * `:username` (required) — the username the password is being set for.
    * `:min_length` (default `#{@default_min_length}`) — minimum number of characters.
    * `:max_length` (default `#{@default_max_length}`) — maximum number of characters.
    * `:require_uppercase` (default `true`) — require an uppercase ASCII letter.
    * `:require_lowercase` (default `true`) — require a lowercase ASCII letter.
    * `:require_digit` (default `true`) — require a digit.
    * `:require_special` (default `true`) — require a non-alphanumeric character.
    * `:common_passwords` (default `[]`) — blocklist, compared case-insensitively.
    * `:previous_passwords` (default `[]`) — prior passwords, compared exactly.
    * `:max_username_similarity` (default `#{@default_max_username_similarity}`) — warn when the
      Levenshtein distance between the password and the username (compared case-insensitively)
      is less than or equal to this value.
    * `:strict` (default `false`) — promote every warning to an error.

  Violations in both lists are ordered canonically: `:too_short`, `:too_long`, `:no_uppercase`,
  `:no_lowercase`, `:no_digit`, `:no_special`, `:common_password`, `:reused_password`,
  `:too_similar_to_username`.

  ## Examples

      iex> PasswordPolicy.audit("Str0ng!Pass", %{username: "alice"})
      %{status: :ok, errors: [], warnings: []}

      iex> PasswordPolicy.audit("abc", %{username: "alice"})
      %{status: :error, errors: [:too_short], warnings: [:no_uppercase, :no_digit, :no_special]}

      iex> PasswordPolicy.audit("abcdefgh", %{username: "alice", strict: true})
      %{status: :error, errors: [:no_uppercase, :no_digit, :no_special], warnings: []}
  """
  @spec audit(String.t(), context()) :: report()
  def audit(password, context) when is_binary(password) and is_map(context) do
    violations = violations(password, context)

    if Map.get(context, :strict, false) do
      %{status: status(violations), errors: violations, warnings: []}
    else
      {errors, warnings} = Enum.split_with(violations, &(&1 in @error_rules))
      %{status: status(errors), errors: errors, warnings: warnings}
    end
  end

  @spec status([rule()]) :: :ok | :error
  defp status([]), do: :ok
  defp status(_violations), do: :error

  @spec violations(String.t(), context()) :: [rule()]
  defp violations(password, context) do
    length = String.length(password)
    username = Map.fetch!(context, :username)

    checks = %{
      too_short: length < Map.get(context, :min_length, @default_min_length),
      too_long: length > Map.get(context, :max_length, @default_max_length),
      no_uppercase: Map.get(context, :require_uppercase, true) and not has_uppercase?(password),
      no_lowercase: Map.get(context, :require_lowercase, true) and not has_lowercase?(password),
      no_digit: Map.get(context, :require_digit, true) and not has_digit?(password),
      no_special: Map.get(context, :require_special, true) and not has_special?(password),
      common_password: common?(password, Map.get(context, :common_passwords, [])),
      reused_password: password in Map.get(context, :previous_passwords, []),
      too_similar_to_username: too_similar?(password, username, context)
    }

    Enum.filter(@canonical_order, &Map.fetch!(checks, &1))
  end

  @spec has_uppercase?(String.t()) :: boolean()
  defp has_uppercase?(password), do: String.match?(password, ~r/[A-Z]/)

  @spec has_lowercase?(String.t()) :: boolean()
  defp has_lowercase?(password), do: String.match?(password, ~r/[a-z]/)

  @spec has_digit?(String.t()) :: boolean()
  defp has_digit?(password), do: String.match?(password, ~r/[0-9]/)

  @spec has_special?(String.t()) :: boolean()
  defp has_special?(password) do
    password
    |> String.graphemes()
    |> Enum.any?(&(not String.match?(&1, ~r/^[A-Za-z0-9]$/)))
  end

  @spec common?(String.t(), [String.t()]) :: boolean()
  defp common?(password, common_passwords) do
    downcased = String.downcase(password)
    Enum.any?(common_passwords, &(String.downcase(&1) == downcased))
  end

  @spec too_similar?(String.t(), String.t(), context()) :: boolean()
  defp too_similar?(password, username, context) do
    max_distance = Map.get(context, :max_username_similarity, @default_max_username_similarity)
    distance = levenshtein(String.downcase(password), String.downcase(username))
    distance <= max_distance
  end

  @doc """
  Computes the Levenshtein edit distance between two strings.

  Implemented with a dynamic-programming row scan over grapheme lists, keeping only the
  previous row in memory. Returns the minimum number of single-character insertions,
  deletions or substitutions required to turn `left` into `right`.

  ## Examples

      iex> PasswordPolicy.levenshtein("kitten", "sitting")
      3

      iex> PasswordPolicy.levenshtein("abc", "abc")
      0
  """
  @spec levenshtein(String.t(), String.t()) :: non_neg_integer()
  def levenshtein(left, right) when is_binary(left) and is_binary(right) do
    do_levenshtein(String.graphemes(left), String.graphemes(right))
  end

  @spec do_levenshtein([String.t()], [String.t()]) :: non_neg_integer()
  defp do_levenshtein(left, right) do
    first_row = Enum.to_list(0..length(right))

    left
    |> Enum.with_index(1)
    |> Enum.reduce(first_row, fn {left_char, row_index}, previous_row ->
      build_row(left_char, row_index, previous_row, right)
    end)
    |> List.last()
  end

  @spec build_row(String.t(), pos_integer(), [non_neg_integer()], [String.t()]) ::
          [non_neg_integer()]
  defp build_row(left_char, row_index, previous_row, right) do
    [diagonal | rest_previous] = previous_row

    {row, _diagonal, _previous} =
      Enum.reduce(right, {[row_index], diagonal, rest_previous}, fn right_char,
                                                                    {acc, diag, [above | tail]} ->
        cost = if left_char == right_char, do: 0, else: 1
        [left_cell | _] = acc
        cell = Enum.min([above + 1, left_cell + 1, diag + cost])
        {[cell | acc], above, tail}
      end)

    Enum.reverse(row)
  end
end