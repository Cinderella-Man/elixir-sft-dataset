# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

Write me an Elixir module called `PasswordPolicy` that audits a password and classifies each failing rule by severity, distinguishing blocking **errors** from non-blocking **warnings**.

I need a single public function:
- `PasswordPolicy.audit(password, context)` which returns a report map of the shape `%{status: :ok | :error, errors: [atom()], warnings: [atom()]}`. `errors` lists every blocking violation, `warnings` lists every advisory violation, and `status` is `:error` when there is at least one error and `:ok` otherwise (warnings alone never change the status to `:error`). Report all violations, not just the first.

Rules are split into two severities:
- **Errors (blocking):** minimum length (`:too_short`), maximum length (`:too_long`), common-password blocklist (`:common_password`), and previously-used-password reuse (`:reused_password`).
- **Warnings (advisory):** missing uppercase (`:no_uppercase`), missing lowercase (`:no_lowercase`), missing digit (`:no_digit`), missing special character (`:no_special`), and being too similar to the username (`:too_similar_to_username`).

The `context` argument is a map that drives configuration and per-user data:
- `:username` (required) — the username the password is being set for.
- `:min_length` (optional, default `8`) — minimum number of characters.
- `:max_length` (optional, default `128`) — maximum number of characters.
- `:require_uppercase` (optional, default `true`) — must contain at least one uppercase ASCII letter.
- `:require_lowercase` (optional, default `true`) — must contain at least one lowercase ASCII letter.
- `:require_digit` (optional, default `true`) — must contain at least one digit.
- `:require_special` (optional, default `true`) — must contain at least one non-alphanumeric character.
- `:common_passwords` (optional, default `[]`) — plaintext strings considered too common; the password must not match any (case-insensitive comparison).
- `:previous_passwords` (optional, default `[]`) — previously used plaintext passwords; the new password must not match any exactly.
- `:max_username_similarity` (optional, default `3`) — the password triggers the similarity warning if its Levenshtein distance from the username (compared case-insensitively) is less than or equal to this value.
- `:strict` (optional, default `false`) — when `true`, every warning is *promoted* to an error: the `warnings` list is emptied, all violations appear in `errors`, and any violation at all forces `status: :error`.

Both `errors` and `warnings` must be listed in this canonical rule order: `:too_short`, `:too_long`, `:no_uppercase`, `:no_lowercase`, `:no_digit`, `:no_special`, `:common_password`, `:reused_password`, `:too_similar_to_username`.

Implement Levenshtein distance yourself using dynamic programming — do not use any external library. All other logic must also use only the Elixir/OTP standard library with no external dependencies.

Give me the complete module in a single file.

## The buggy module

```elixir
defmodule PasswordPolicy do
  @moduledoc """
  Audits a password and classifies each failing rule by severity, separating
  blocking errors from non-blocking warnings. In `:strict` mode, warnings are
  promoted to errors.

  ## Usage

      PasswordPolicy.audit("abc", %{username: "operator"})
      # => %{status: :error, errors: [:too_short],
      #      warnings: [:no_uppercase, :no_digit, :no_special]}
  """

  @default_min_length 8
  @default_max_length 128
  @default_require_uppercase true
  @default_require_lowercase true
  @default_require_digit true
  @default_require_special true
  @default_common_passwords []
  @default_previous_passwords []
  @default_max_username_similarity 3
  @default_strict false

  # Violations that block (become part of `errors` and force status: :error).
  @error_atoms [:too_short, :too_long, :common_password, :reused_password]

  @spec audit(String.t(), map()) :: %{
          status: :ok | :error,
          errors: [atom()],
          warnings: [atom()]
        }
  def audit(password, %{username: _} = context) do
    cfg = build_config(context)
    all = all_violations(password, cfg)

    {errors, warnings} =
      if cfg.strict do
        {all, []}
      else
        Enum.split_with(all, fn v -> v in @error_atoms end)
      end

    status = if errors == [], do: :error, else: :error
    %{status: status, errors: errors, warnings: warnings}
  end

  def audit(_password, _context) do
    raise ArgumentError, "context map must include the :username key"
  end

  # ---------------------------------------------------------------------------
  # Config
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
        Map.get(context, :max_username_similarity, @default_max_username_similarity),
      strict: Map.get(context, :strict, @default_strict)
    }
  end

  # ---------------------------------------------------------------------------
  # Violation collection (canonical rule order)
  # ---------------------------------------------------------------------------

  defp all_violations(password, cfg) do
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
  end

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
    if String.match?(password, ~r/[^a-zA-Z0-9]/), do: :ok, else: {:violation, :no_special}
  end

  defp check_common(password, %{common_passwords: list}) do
    lower = String.downcase(password)

    if Enum.any?(list, fn p -> String.downcase(p) == lower end),
      do: {:violation, :common_password},
      else: :ok
  end

  defp check_reuse(password, %{previous_passwords: list}) do
    if password in list, do: {:violation, :reused_password}, else: :ok
  end

  defp check_username_similarity(password, %{
         username: username,
         max_username_similarity: threshold
       }) do
    dist = levenshtein(String.downcase(password), String.downcase(username))
    if dist > threshold, do: :ok, else: {:violation, :too_similar_to_username}
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
3 of 10 test(s) failed:

  * test warnings alone do not flip the status to error
      
      
      Assertion with == failed
      code:  assert report == %{status: :ok, errors: [], warnings: [:no_uppercase, :no_digit, :no_special]}
      left:  %{status: :error, errors: [], warnings: [:no_uppercase, :no_digit, :no_special]}
      right: %{status: :ok, errors: [], warnings: [:no_uppercase, :no_digit, :no_special]}
      

  * test username similarity is a warning, not an error, by default
      
      
      Assertion with == failed
      code:  assert report == %{status: :ok, errors: [], warnings: [:too_similar_to_username]}
      left:  %{status: :error, errors: [], warnings: [:too_similar_to_username]}
      right: %{status: :ok, errors: [], warnings: [:too_similar_to_username]}
      

  * test a fully valid password produces an empty ok report
      
      
      Assertion with == failed
      code:  assert report == %{status: :ok, errors: [], warnings: []}
      left:  %{status: :error, errors: [], warnings: []}
      right: %{status: :ok, errors: [], warnings: []}
```
