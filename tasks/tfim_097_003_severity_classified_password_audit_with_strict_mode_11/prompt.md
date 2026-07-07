# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule PasswordPolicyV2Test do
  use ExUnit.Case, async: false

  # Exercises the severity-classified audit variant of PasswordPolicy.audit/2,
  # including the :strict promotion of warnings to errors.

  test "weak short password splits into a blocking error and advisory warnings" do
    report = PasswordPolicy.audit("abc", %{username: "operator"})

    assert report == %{
             status: :error,
             errors: [:too_short],
             warnings: [:no_uppercase, :no_digit, :no_special]
           }
  end

  test "warnings alone do not flip the status to error" do
    # "abcdefgh": length 8 (ok), lowercase only. Only advisory violations.
    report = PasswordPolicy.audit("abcdefgh", %{username: "operator"})

    assert report == %{
             status: :ok,
             errors: [],
             warnings: [:no_uppercase, :no_digit, :no_special]
           }
  end

  test "strict mode promotes all warnings into errors and fails the status" do
    report = PasswordPolicy.audit("abcdefgh", %{username: "operator", strict: true})

    assert report == %{
             status: :error,
             errors: [:no_uppercase, :no_digit, :no_special],
             warnings: []
           }
  end

  test "common password is a blocking error" do
    report =
      PasswordPolicy.audit("Password1!", %{
        username: "operator",
        common_passwords: ["password1!"]
      })

    assert report == %{status: :error, errors: [:common_password], warnings: []}
  end

  test "reused password is a blocking error" do
    report =
      PasswordPolicy.audit("Secret9!x", %{
        username: "operator",
        previous_passwords: ["Secret9!x"]
      })

    assert report == %{status: :error, errors: [:reused_password], warnings: []}
  end

  test "username similarity is a warning, not an error, by default" do
    # Differs from the username by one character -> distance 1 (<= 3), otherwise strong.
    report = PasswordPolicy.audit("Xy9#Kw2$Lm", %{username: "Xy9#Kw2$Lp"})

    assert report == %{status: :ok, errors: [], warnings: [:too_similar_to_username]}
  end

  test "username similarity becomes an error under strict mode" do
    report = PasswordPolicy.audit("Xy9#Kw2$Lm", %{username: "Xy9#Kw2$Lp", strict: true})

    assert report == %{status: :error, errors: [:too_similar_to_username], warnings: []}
  end

  test "a fully valid password produces an empty ok report" do
    report =
      PasswordPolicy.audit("Tr0ub4dor&3", %{
        username: "alice",
        common_passwords: ["password123"],
        previous_passwords: ["OldPass1!"]
      })

    assert report == %{status: :ok, errors: [], warnings: []}
  end

  test "mixed errors and warnings keep canonical ordering" do
    report = PasswordPolicy.audit("abc", %{username: "operator"})
    assert report.errors == [:too_short]
    assert report.warnings == [:no_uppercase, :no_digit, :no_special]

    strict = PasswordPolicy.audit("abc", %{username: "operator", strict: true})
    assert strict.errors == [:too_short, :no_uppercase, :no_digit, :no_special]
    assert strict.warnings == []
  end

  test "raises when the context is missing the username" do
    # TODO
  end
end
```
