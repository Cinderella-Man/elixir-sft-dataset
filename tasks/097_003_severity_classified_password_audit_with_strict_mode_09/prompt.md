# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `check_lowercase` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

I need a password auditing module and I'd rather describe it to you than write it myself. Call it `PasswordPolicy`. The idea is that it audits a password and classifies each failing rule by severity, so we can distinguish blocking **errors** from non-blocking **warnings**.

There's just one public function I want: `PasswordPolicy.audit(password, context)`. It returns a report map shaped like `%{status: :ok | :error, errors: [atom()], warnings: [atom()]}`. The `errors` key lists every blocking violation, `warnings` lists every advisory violation, and `status` comes out as `:error` when there's at least one error and `:ok` otherwise — warnings on their own never flip the status to `:error`. Important: report all violations, not just the first one you hit.

The rules split into two severities. The blocking errors are minimum length (`:too_short`), maximum length (`:too_long`), the common-password blocklist (`:common_password`), and reuse of a previously-used password (`:reused_password`). The advisory warnings are missing uppercase (`:no_uppercase`), missing lowercase (`:no_lowercase`), missing digit (`:no_digit`), missing special character (`:no_special`), and being too similar to the username (`:too_similar_to_username`).

The `context` argument is a map that carries both the configuration and the per-user data. `:username` is required — it's the username the password is being set for — and if `context` doesn't contain a `:username` key, I want you to raise `ArgumentError`. Everything else is optional with a default: `:min_length` (default `8`) is the minimum number of characters; `:max_length` (default `128`) is the maximum; `:require_uppercase` (default `true`) means the password must contain at least one uppercase ASCII letter; `:require_lowercase` (default `true`) means at least one lowercase ASCII letter; `:require_digit` (default `true`) means at least one digit; `:require_special` (default `true`) means at least one non-alphanumeric character; `:common_passwords` (default `[]`) is a list of plaintext strings considered too common, and the password must not match any of them, compared case-insensitively; `:previous_passwords` (default `[]`) is a list of previously used plaintext passwords, and the new password must not match any of them exactly; `:max_username_similarity` (default `3`) means the password triggers the similarity warning if its Levenshtein distance from the username — compared case-insensitively — is less than or equal to that value; and `:strict` (default `false`), which when set to `true` *promotes* every warning to an error: the `warnings` list comes back empty, all violations show up in `errors`, and any violation at all forces `status: :error`.

One more thing on output: both `errors` and `warnings` have to be listed in this canonical rule order — `:too_short`, `:too_long`, `:no_uppercase`, `:no_lowercase`, `:no_digit`, `:no_special`, `:common_password`, `:reused_password`, `:too_similar_to_username`.

Please implement Levenshtein distance yourself with dynamic programming — no external library for it. Same goes for the rest of the logic: Elixir/OTP standard library only, no external dependencies.

Send me back the complete module in a single file.

## The module with `check_lowercase` missing

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

    status = if errors == [], do: :ok, else: :error
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

  defp check_lowercase(_password, %{require_lowercase: false}) do
    # TODO
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

Give me only the complete implementation of `check_lowercase` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
