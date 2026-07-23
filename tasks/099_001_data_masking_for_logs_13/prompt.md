# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `digit?` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

# Design brief: `LogMasker`

## Problem

Log-bound payloads in our system arrive as maps, keyword lists, and raw strings, and they routinely carry sensitive data — passwords, tokens, SSNs, credit card numbers, email addresses. We need a single Elixir module, `LogMasker`, that scrubs sensitive data from log-bound maps, keyword lists, and strings before they reach the log sink.

## Constraints

- Deliver the complete module in a single file.
- Use only the Elixir standard library and built-in regex support — no external dependencies.

## Required interface

1. **`LogMasker.new(sensitive_keys)`** — creates a masker configuration. `sensitive_keys` is a list of atoms (e.g. `[:password, :ssn, :credit_card, :token]`). Return an opaque struct or map that can be passed to the other functions.

2. **`LogMasker.mask(masker, data)`** — accepts either a map, a keyword list, or a string, and returns the same type with sensitive data scrubbed.
   - For maps and keyword lists, recursively walk all values. If a key matches a sensitive key (comparison should be case-insensitive and work for both atom and string keys), replace its value with `"[MASKED]"` regardless of what the value is.
   - Lists of maps or keyword lists should also be walked recursively.
   - Non-sensitive keys must be left completely untouched.

3. **`LogMasker.mask_string(masker, string)`** — scans a raw string and masks three patterns:
   1. **Credit card numbers**: any sequence of 13–19 digits (optionally separated by spaces or hyphens) — replace all digit groups except the last 4 digits with `*` characters of equal length, keeping separators intact. E.g. `"4111-1111-1111-1234"` → `"****-****-****-1234"`.
   2. **Email addresses**: mask the local part (before `@`) keeping only the first character and replacing the rest with `***`. E.g. `"john.doe@example.com"` → `"j***@example.com"`. A single-character local part like `"a@b.com"` becomes `"a***@b.com"`.
   3. **SSN patterns**: sequences matching `\d{3}-\d{2}-\d{4}` — replace with `"***-**-****"`.

   Mask SSN patterns before applying the credit-card pattern, so that two adjacent SSNs are each replaced independently rather than being consumed as one long credit-card number. E.g. `"123-45-6789 987-65-4321"` → `"***-**-**** ***-**-****"` (no trailing digits left visible).

4. **Cross-cutting behavior of `LogMasker.mask/2`** — it should also apply `mask_string/2` to any string *values* it encounters while walking a map or keyword list, even for non-sensitive keys, so stray PII embedded in strings is caught everywhere. A masker built from an empty `sensitive_keys` list therefore masks nothing by key, but still pattern-masks string values it encounters.

## Acceptance criteria

- `LogMasker.new/1` returns a configuration value (opaque struct or map) accepted by the other functions.
- Given a map or keyword list, `LogMasker.mask/2` returns the same type, with every sensitive-key value replaced by `"[MASKED]"` whatever that value was, matching keys case-insensitively across both atom and string keys, and recursing through nested maps, nested keyword lists, and lists of maps or keyword lists.
- Values under non-sensitive keys are otherwise left completely untouched, aside from string values, which are passed through `mask_string/2`.
- Given a string, `LogMasker.mask/2` returns a string.
- `LogMasker.mask_string/2` yields `"****-****-****-1234"` for `"4111-1111-1111-1234"`, `"j***@example.com"` for `"john.doe@example.com"`, `"a***@b.com"` for `"a@b.com"`, `"***-**-****"` for any `\d{3}-\d{2}-\d{4}` match, and `"***-**-**** ***-**-****"` for `"123-45-6789 987-65-4321"`.
- Credit-card masking covers digit sequences of 13–19 digits with optional space or hyphen separators, preserves those separators, preserves the last 4 digits, and replaces each other digit group with an equal-length run of `*`.
- An empty `sensitive_keys` list masks nothing by key while still pattern-masking encountered string values.
- The module compiles and runs against the Elixir standard library and built-in regex support alone, in one file.

## The module with `digit?` missing

```elixir
defmodule LogMasker do
  @moduledoc """
  Scrubs sensitive data from log-bound maps, keyword lists, and strings.

  ## Usage

      iex> masker = LogMasker.new([:password, :ssn, :credit_card, :token])
      iex> LogMasker.mask(masker, %{user: "jane", password: "hunter2"})
      %{user: "jane", password: "[MASKED]"}

      iex> LogMasker.mask_string(masker, "card 4111-1111-1111-1234, email a@b.com")
      "card ****-****-****-1234, email a***@b.com"
  """

  @enforce_keys [:sensitive_keys]
  defstruct sensitive_keys: MapSet.new()

  @opaque t :: %__MODULE__{sensitive_keys: MapSet.t(String.t())}

  @mask "[MASKED]"

  # Credit card: 13–19 digits, optionally separated by spaces or hyphens.
  #   \b  — word boundary so we don't anchor mid-digit
  #   \d  — first digit
  #   (?:[\s-]?\d){12,18} — 12..18 more "optional-sep + digit" pairs → 13..19 digits total
  @cc_regex ~r/\b\d(?:[\s-]?\d){12,18}\b/

  # Email: standard local@domain with TLD.
  @email_regex ~r/([A-Za-z0-9._%+\-]+)@([A-Za-z0-9.\-]+\.[A-Za-z]{2,})/

  # US Social Security number pattern.
  @ssn_regex ~r/\b\d{3}-\d{2}-\d{4}\b/

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Builds an opaque masker configuration from a list of sensitive keys.

  Keys may be atoms or strings. Comparison at mask time is case-insensitive,
  so `:Password`, `"password"`, and `"PASSWORD"` are all treated equivalently
  to `:password`.
  """
  @spec new([atom() | String.t()]) :: t()
  def new(sensitive_keys) when is_list(sensitive_keys) do
    normalized =
      sensitive_keys
      |> Enum.map(&normalize_key/1)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    %__MODULE__{sensitive_keys: normalized}
  end

  @doc """
  Masks sensitive data in a map, keyword list, or string.

  * Maps and keyword lists are walked recursively. Values under sensitive keys
    are replaced with `"[MASKED]"` regardless of the original value. Non-sensitive
    keys are preserved, and their values continue to be scrubbed.
  * Plain lists (and lists of maps / keyword lists) are walked element-by-element.
  * String values are always passed through `mask_string/2`, so embedded PII
    (credit cards, emails, SSNs) is scrubbed everywhere — even under keys
    that were not marked sensitive.
  * Structs and other terms are returned unchanged.
  """
  @spec mask(t(), term()) :: term()
  def mask(%__MODULE__{} = masker, data), do: do_mask(masker, data)

  @doc """
  Masks credit card numbers, email addresses, and SSN patterns inside a raw string.

  * SSNs (`\\d{3}-\\d{2}-\\d{4}`): replaced with `***-**-****`. SSNs are masked
    first so that adjacent SSNs are never swallowed by the broader credit card
    pattern (which would otherwise leave a trailing four digits visible).
  * Credit cards (13–19 digits, optionally separated by spaces or hyphens):
    all digits except the final four are replaced with `*`, separators kept.
  * Emails: the local part keeps only its first character; the rest becomes `***`.
  """
  @spec mask_string(t(), String.t()) :: String.t()
  def mask_string(%__MODULE__{}, string) when is_binary(string) do
    string
    |> mask_ssns()
    |> mask_credit_cards()
    |> mask_emails()
  end

  # ---------------------------------------------------------------------------
  # Recursive walk
  # ---------------------------------------------------------------------------

  # Plain maps (not structs): walk entries.
  defp do_mask(masker, data) when is_map(data) and not is_struct(data) do
    Map.new(data, fn {k, v} ->
      if sensitive_key?(masker, k) do
        {k, @mask}
      else
        {k, do_mask(masker, v)}
      end
    end)
  end

  # Lists: keyword lists get key-aware handling; otherwise walk elements.
  defp do_mask(masker, data) when is_list(data) do
    if keyword_list?(data) do
      Enum.map(data, fn {k, v} ->
        if sensitive_key?(masker, k) do
          {k, @mask}
        else
          {k, do_mask(masker, v)}
        end
      end)
    else
      Enum.map(data, &do_mask(masker, &1))
    end
  end

  # Strings: route through mask_string/2 so embedded PII is scrubbed.
  defp do_mask(masker, data) when is_binary(data), do: mask_string(masker, data)

  # Structs, numbers, atoms, tuples, pids, etc.: leave untouched.
  defp do_mask(_masker, data), do: data

  # ---------------------------------------------------------------------------
  # String scrubbers
  # ---------------------------------------------------------------------------

  defp mask_credit_cards(string) do
    Regex.replace(@cc_regex, string, &mask_cc_match/1)
  end

  # Build the masked replacement by walking the matched span one char at a time,
  # replacing every digit with `*` except the final four.
  defp mask_cc_match(match) do
    chars = String.graphemes(match)
    digit_count = Enum.count(chars, &digit?/1)
    keep_threshold = digit_count - 4

    {reversed, _seen} =
      Enum.reduce(chars, {[], 0}, fn ch, {acc, seen} ->
        if digit?(ch) do
          seen = seen + 1
          replacement = if seen > keep_threshold, do: ch, else: "*"
          {[replacement | acc], seen}
        else
          {[ch | acc], seen}
        end
      end)

    reversed |> Enum.reverse() |> Enum.join()
  end

  defp mask_ssns(string) do
    Regex.replace(@ssn_regex, string, "***-**-****")
  end

  defp mask_emails(string) do
    Regex.replace(@email_regex, string, fn _full, local, domain ->
      first = String.first(local) || ""
      "#{first}***@#{domain}"
    end)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp sensitive_key?(%__MODULE__{sensitive_keys: keys}, key) do
    case normalize_key(key) do
      nil -> false
      norm -> MapSet.member?(keys, norm)
    end
  end

  defp normalize_key(key) when is_atom(key), do: key |> Atom.to_string() |> String.downcase()
  defp normalize_key(key) when is_binary(key), do: String.downcase(key)
  defp normalize_key(_), do: nil

  defp keyword_list?([]), do: false

  defp keyword_list?(list) when is_list(list) do
    Enum.all?(list, fn
      {k, _v} when is_atom(k) -> true
      _ -> false
    end)
  end

  defp digit?(<<c>>) when c in ?0..?9 do
    # TODO
  end
end
```

Give me only the complete implementation of `digit?` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
