# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `common_reason` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

# `PasswordPolicy` — Weighted Password Strength Specification

## Overview

This document specifies an Elixir module named `PasswordPolicy`. Rather than treating every rule as an equal pass/fail gate, the module scores password *strength* on a 0–100 scale and accepts or rejects a candidate password based on a configurable threshold. The deliverable is the complete module in a single file.

The implementation must rely solely on the Elixir/OTP standard library; no external dependencies are permitted for any part of the logic. In particular, Levenshtein distance must be implemented within the module itself using dynamic programming, not taken from an external library.

## API

The module exposes exactly one public function:

- `PasswordPolicy.evaluate(password, context)` — returns `{:accepted, score}` when the password clears every hard rule **and** its strength score meets the minimum, or `{:rejected, score, reasons}`, where `reasons` is a list of atoms describing every reason the password was rejected (all applicable reasons are reported, not just the first). `score` is always the computed integer strength score and is present in both the accepted and the rejected result.

### The `context` argument

The `context` argument is a map that supplies configuration and per-user data:

- `:username` (required) — the username the password is being set for. If the context map does not include `:username`, `evaluate/2` must raise an `ArgumentError`.
- `:min_length` (optional, default `8`) — a *hard* minimum; shorter passwords are rejected with `:too_short` regardless of score.
- `:min_score` (optional, default `60`) — the minimum strength score required; passwords scoring strictly below this value are rejected with `:insufficient_strength`.
- `:common_passwords` (optional, default `[]`) — a list of plaintext strings considered too common; a case-insensitive match is a hard rejection with `:common_password`.
- `:max_username_similarity` (optional, default `3`) — the password is rejected with `:too_similar_to_username` if its Levenshtein distance from the username (compared case-insensitively) is less than or equal to this value.

## Scoring model

The strength score is computed deterministically as the sum, capped at `100`, of the following components:

- **Length points:** `2` points per character, counting at most `20` characters (so `0`–`40`).
- **Character-class points:** `10` points for each of the following classes present at least once — uppercase ASCII letter, lowercase ASCII letter, digit, and non-alphanumeric ("special") character (so `0`–`40`).
- **Length bonus:** a flat `20` points if the password is at least `16` characters long.

## Edge cases

- The rejection atoms in use are: `:too_short`, `:common_password`, `:too_similar_to_username`, `:insufficient_strength`. When multiple apply, they are listed in that canonical order.
- A missing `:username` key in `context` raises an `ArgumentError`.
- Common-password matching is case-insensitive; username-similarity comparison is likewise case-insensitive.
- A password shorter than `:min_length` is rejected with `:too_short` no matter how it scores.
- A score strictly below `:min_score` yields `:insufficient_strength`.
- A Levenshtein distance from the username less than or equal to `:max_username_similarity` yields `:too_similar_to_username`.

## The module with `common_reason` missing

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

  @doc """
  Evaluates `password` against the policy configured by `context`.

  Returns `{:accepted, score}` when every check passes, or
  `{:rejected, score, reasons}` with the failed checks as atoms. The
  `context` map must include `:username`; raising `ArgumentError` otherwise.
  """
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
    # TODO
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

  @spec levenshtein(String.t(), String.t()) :: non_neg_integer()
  defp levenshtein(a, b) when is_binary(a) and is_binary(b) do
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

Give me only the complete implementation of `common_reason` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
