Implement the private `all_violations/2` function. It receives the `password`
string and the normalized `cfg` map produced by `build_config/1`, and returns a
list of violation atoms — one entry for every rule the password fails —
in the canonical rule order.

It must run each of the nine per-rule checks against the password and config, in
this exact order: `check_min_length/2`, `check_max_length/2`,
`check_uppercase/2`, `check_lowercase/2`, `check_digit/2`, `check_special/2`,
`check_common/2`, `check_reuse/2`, and `check_username_similarity/2`. Each check
returns either `:ok` (rule satisfied) or `{:violation, atom}` (rule failed).
Collect the atoms from every check that returns a violation, dropping the ones
that return `:ok`, and return them as a list preserving the canonical order in
which the checks were run (so the resulting list is already in the order
`:too_short`, `:too_long`, `:no_uppercase`, `:no_lowercase`, `:no_digit`,
`:no_special`, `:common_password`, `:reused_password`,
`:too_similar_to_username`). If no rule fails, return an empty list.

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
    # TODO
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