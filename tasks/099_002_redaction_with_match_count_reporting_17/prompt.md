# Implement the missing function

The specification below is followed by its complete, tested solution —
minus `normalize_key`, whose clause bodies are all `# TODO`. Supply that one
function; the rest of the module is fixed and must stay exactly as shown.

## The task

# Specification — `LogRedactor`: Redaction With Match-Count Reporting

## Overview

This document specifies an Elixir module named `LogRedactor` that scrubs sensitive data from log-bound maps, keyword lists, and strings **and reports how much it scrubbed**. The module follows the same idea as a basic log masker, with one addition: every operation must hand back a *redaction report*, so that callers can emit metrics about how much PII a payload contained.

## Public API

The module exposes the following three functions.

### `LogRedactor.new(sensitive_keys)`

Creates a redactor configuration. `sensitive_keys` is a list of atoms and/or strings (e.g. `[:password, :ssn, :token]`). Comparison at redaction time must be case-insensitive and work for both atom and string keys. The function returns an opaque struct or map that can be passed to the other functions.

### `LogRedactor.redact(redactor, data)`

Accepts a map, a keyword list, a plain list, or any other term, and returns a **tuple** `{scrubbed, report}`.

- `scrubbed` is the same shape as the input with sensitive data removed.
- Maps and keyword lists are walked recursively. If a key matches a sensitive key, its value is replaced with the string `"[REDACTED]"` regardless of the value's type (integer, nil, list, string, …). Non-sensitive keys are preserved, and their values continue to be walked.
- Plain lists (including lists of maps or keyword lists) are walked element-by-element.
- Every **string value** encountered under a non-sensitive key is passed through the same pattern scrubbing as `redact_string/2` (described below), so that stray PII embedded in free text is caught everywhere. Values replaced with `"[REDACTED]"` because of a sensitive key are **not** additionally pattern-scanned.
- Structs, numbers, atoms, and other terms are returned unchanged.

### `LogRedactor.redact_string(redactor, string)`

Scans a raw string, masks the three patterns described below, and returns `{scrubbed_string, report}`. The report has the same four keys; `:keys_masked` is always `0` for this function, and the other three count how many matches of each pattern were masked in the string.

## Report structure

`report` is a map with exactly these four integer keys:

- `:keys_masked` — how many values were replaced with `"[REDACTED]"` because their key was sensitive (counted across the whole recursive walk).
- `:credit_cards` — how many credit-card matches were masked across all scanned strings.
- `:emails` — how many email matches were masked across all scanned strings.
- `:ssns` — how many SSN matches were masked across all scanned strings.

## String patterns

Three patterns are scrubbed, using scrubbing rules identical to those of a standard masker.

- **Credit card numbers**: any sequence of 13–19 digits (optionally separated by single spaces or hyphens) — every digit except the last 4 is replaced with a `*`, keeping separators intact. E.g. `"4111-1111-1111-1234"` → `"****-****-****-1234"`.
- **Email addresses**: only the first character of the local part (before `@`) is kept, and the rest is replaced with `***`. E.g. `"john.doe@example.com"` → `"j***@example.com"`.
- **SSN patterns**: sequences matching `\d{3}-\d{2}-\d{4}` are replaced with `"***-**-****"`.

## Edge cases

- For an input with nothing to scrub (e.g. an empty map), the report is `%{keys_masked: 0, credit_cards: 0, emails: 0, ssns: 0}`.
- Sensitive-key matching is case-insensitive and applies to atom keys and string keys alike.
- A value masked as `"[REDACTED]"` due to a sensitive key is never scanned again for the three string patterns.
- Values of any type (integer, nil, list, string, …) under a sensitive key become `"[REDACTED]"`.
- Structs, numbers, atoms, and other terms pass through unchanged.

## Delivery constraints

The complete module is delivered in a single file. Only the Elixir standard library and built-in regex support may be used — no external dependencies.

## The module with `normalize_key` missing

```elixir
defmodule LogRedactor do
  @moduledoc """
  Scrubs sensitive data from log-bound maps, keyword lists, plain lists, and
  strings while reporting how much was scrubbed.

  Every public operation returns a `{scrubbed, report}` tuple so callers can
  emit metrics about how much PII a payload contained. Redaction happens in
  two ways:

    * **Sensitive keys** — values whose key matches a configured sensitive key
      (case-insensitively, for atom or string keys) are replaced with the
      string `"[REDACTED]"`.
    * **Pattern scrubbing** — every string encountered under a non-sensitive
      key (and any raw string passed to `redact_string/2`) is scanned for
      credit-card numbers, email addresses, and SSNs, which are masked in
      place.

  The report is always a map with exactly the keys `:keys_masked`,
  `:credit_cards`, `:emails`, and `:ssns`.
  """

  @enforce_keys [:keys]
  defstruct keys: MapSet.new()

  @type t :: %__MODULE__{keys: MapSet.t()}

  @type report :: %{
          keys_masked: non_neg_integer(),
          credit_cards: non_neg_integer(),
          emails: non_neg_integer(),
          ssns: non_neg_integer()
        }

  @empty_report %{keys_masked: 0, credit_cards: 0, emails: 0, ssns: 0}

  # 13-19 digits, optionally separated by single spaces or hyphens.
  @cc_regex ~r/\d(?:[ -]?\d){12,18}/

  @ssn_regex ~r/\d{3}-\d{2}-\d{4}/

  @email_regex ~r/([A-Za-z0-9._%+\-]+)@([A-Za-z0-9.\-]+\.[A-Za-z]{2,})/

  @doc """
  Builds an opaque redactor configuration from a list of sensitive keys.

  `sensitive_keys` may contain atoms and/or strings. Comparisons performed at
  redaction time are case-insensitive and match both atom and string keys.
  """
  @spec new([atom() | String.t()]) :: t()
  def new(sensitive_keys) when is_list(sensitive_keys) do
    set =
      sensitive_keys
      |> Enum.map(&normalize_key/1)
      |> MapSet.new()

    %__MODULE__{keys: set}
  end

  @doc """
  Redacts `data`, returning `{scrubbed, report}`.

  Maps and keyword lists are walked recursively; plain lists are walked
  element-by-element. Sensitive keys have their values replaced with
  `"[REDACTED]"`, while every other string is pattern-scrubbed. Structs,
  numbers, atoms, and other terms are returned unchanged.
  """
  @spec redact(t(), term()) :: {term(), report()}
  def redact(%__MODULE__{} = redactor, data), do: walk(redactor, data)

  @doc """
  Scrubs the three sensitive patterns (credit cards, emails, SSNs) from a raw
  string and returns `{scrubbed_string, report}`.

  `:keys_masked` is always `0` for this function; the other three counters
  report how many matches of each pattern were masked.
  """
  @spec redact_string(t(), String.t()) :: {String.t(), report()}
  def redact_string(%__MODULE__{} = _redactor, string) when is_binary(string) do
    scrub_string(string)
  end

  # --- Recursive walk -------------------------------------------------------

  @spec walk(t(), term()) :: {term(), report()}
  defp walk(redactor, data) do
    cond do
      is_struct(data) -> {data, @empty_report}
      is_map(data) -> walk_map(redactor, data)
      is_list(data) -> walk_any_list(redactor, data)
      is_binary(data) -> scrub_string(data)
      true -> {data, @empty_report}
    end
  end

  @spec walk_any_list(t(), list()) :: {list(), report()}
  defp walk_any_list(redactor, list) do
    if Keyword.keyword?(list) and list != [] do
      walk_keyword(redactor, list)
    else
      walk_list(redactor, list)
    end
  end

  @spec walk_map(t(), map()) :: {map(), report()}
  defp walk_map(redactor, map) do
    Enum.reduce(map, {%{}, @empty_report}, fn {k, v}, {acc, rep} ->
      {new_v, new_rep} = redact_pair(redactor, k, v)
      {Map.put(acc, k, new_v), merge(rep, new_rep)}
    end)
  end

  @spec walk_keyword(t(), keyword()) :: {keyword(), report()}
  defp walk_keyword(redactor, kw) do
    {acc, rep} =
      Enum.reduce(kw, {[], @empty_report}, fn {k, v}, {acc, rep} ->
        {new_v, new_rep} = redact_pair(redactor, k, v)
        {[{k, new_v} | acc], merge(rep, new_rep)}
      end)

    {Enum.reverse(acc), rep}
  end

  @spec walk_list(t(), list()) :: {list(), report()}
  defp walk_list(redactor, list) do
    {acc, rep} =
      Enum.reduce(list, {[], @empty_report}, fn el, {acc, rep} ->
        {new_el, new_rep} = walk(redactor, el)
        {[new_el | acc], merge(rep, new_rep)}
      end)

    {Enum.reverse(acc), rep}
  end

  @spec redact_pair(t(), term(), term()) :: {term(), report()}
  defp redact_pair(redactor, key, value) do
    if sensitive?(redactor, key) do
      {"[REDACTED]", %{@empty_report | keys_masked: 1}}
    else
      walk(redactor, value)
    end
  end

  # --- String scrubbing -----------------------------------------------------

  @spec scrub_string(String.t()) :: {String.t(), report()}
  defp scrub_string(string) do
    {s1, cards} = mask_credit_cards(string)
    {s2, ssns} = mask_ssns(s1)
    {s3, emails} = mask_emails(s2)

    {s3, %{keys_masked: 0, credit_cards: cards, emails: emails, ssns: ssns}}
  end

  @spec mask_credit_cards(String.t()) :: {String.t(), non_neg_integer()}
  defp mask_credit_cards(string) do
    count = length(Regex.scan(@cc_regex, string))
    scrubbed = Regex.replace(@cc_regex, string, &mask_cc_match/1)
    {scrubbed, count}
  end

  @spec mask_cc_match(String.t()) :: String.t()
  defp mask_cc_match(match) do
    digits = for <<c <- match>>, c in ?0..?9, do: c
    mask_until = length(digits) - 4

    {chars, _idx} =
      match
      |> to_charlist()
      |> Enum.reduce({[], 0}, fn ch, {acc, idx} ->
        if ch in ?0..?9 do
          new_ch = if idx < mask_until, do: ?*, else: ch
          {[new_ch | acc], idx + 1}
        else
          {[ch | acc], idx}
        end
      end)

    chars |> Enum.reverse() |> List.to_string()
  end

  @spec mask_ssns(String.t()) :: {String.t(), non_neg_integer()}
  defp mask_ssns(string) do
    count = length(Regex.scan(@ssn_regex, string))
    {Regex.replace(@ssn_regex, string, "***-**-****"), count}
  end

  @spec mask_emails(String.t()) :: {String.t(), non_neg_integer()}
  defp mask_emails(string) do
    count = length(Regex.scan(@email_regex, string))

    scrubbed =
      Regex.replace(@email_regex, string, fn _full, local, domain ->
        "#{String.first(local)}***@#{domain}"
      end)

    {scrubbed, count}
  end

  # --- Key helpers ----------------------------------------------------------

  @spec sensitive?(t(), term()) :: boolean()
  defp sensitive?(redactor, key) do
    case key_string(key) do
      nil -> false
      norm -> MapSet.member?(redactor.keys, norm)
    end
  end

  defp normalize_key(key) when is_atom(key) do
    # TODO
  end

  @spec key_string(term()) :: String.t() | nil
  defp key_string(key) when is_atom(key), do: key |> Atom.to_string() |> String.downcase()
  defp key_string(key) when is_binary(key), do: String.downcase(key)
  defp key_string(_key), do: nil

  @spec merge(report(), report()) :: report()
  defp merge(a, b), do: Map.merge(a, b, fn _k, v1, v2 -> v1 + v2 end)
end
```

Output only `normalize_key` (with any `@doc`/`@spec`/`@impl` lines that belong
directly above it) — the single function, not the module.
