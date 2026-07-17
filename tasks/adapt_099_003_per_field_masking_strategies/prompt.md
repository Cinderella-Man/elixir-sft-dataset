# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

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

  defp digit?(<<c>>) when c in ?0..?9, do: true
  defp digit?(_), do: false
end
```

## New specification

Write me an Elixir module called `FieldMasker` that scrubs sensitive data from log-bound maps, keyword lists, and strings, where **each sensitive key is masked according to its own strategy** rather than every sensitive value being blanked identically.

I need these functions in the public API:

- `FieldMasker.new(policies)` — creates a masker configuration. `policies` is either a map or a keyword list mapping a key (atom and/or string) to a masking strategy. Comparison at mask time must be case-insensitive and work for both atom and string keys. Return an opaque struct or map that can be passed to the other functions. The valid strategies are:
  - `:redact` — replace the value with the string `"[MASKED]"` regardless of its type.
  - `:last4` — for a string value, keep the last 4 characters and replace every earlier character with a single `*` (so `"4111111111111234"` → `"************1234"`); if the string has 4 or fewer characters, replace every character with a `*` (so `"ab"` → `"**"` and `""` → `""`); if the value is **not** a string, replace it with `"[MASKED]"`.
  - `:hash` — replace the value with `"sha256:"` followed by the lowercase hex SHA-256 digest of the value. Use the value itself when it is a string; otherwise use its `inspect/1` representation. For example the masked value for `"hunter2"` is `"sha256:"` concatenated with `Base.encode16(:crypto.hash(:sha256, "hunter2"), case: :lower)`.

- `FieldMasker.mask(masker, data)` — accepts a map, a keyword list, a plain list, or any other term, and returns the same shape with sensitive data scrubbed.
  - Maps and keyword lists are walked recursively. If a key appears in `policies`, its value is replaced by applying that key's strategy (as described above). Non-policy keys are preserved and their values continue to be walked.
  - Plain lists (including lists of maps or keyword lists) are walked element-by-element.
  - Every **string value** encountered under a key that is **not** in `policies` is passed through the same pattern scrubbing as `mask_string/2` (see below), so stray PII in free text is still caught. A value transformed by a strategy is **not** additionally pattern-scanned.
  - Structs, numbers, atoms, and other terms with no matching policy key are returned unchanged.

- `FieldMasker.mask_string(masker, string)` — scans a raw string and masks these three patterns:
  - **Credit card numbers**: any sequence of 13–19 digits (optionally separated by single spaces or hyphens) — replace every digit except the last 4 with `*`, keeping separators intact. E.g. `"4111-1111-1111-1234"` → `"****-****-****-1234"`.
  - **Email addresses**: keep only the first character of the local part and replace the rest with `***`. E.g. `"john.doe@example.com"` → `"j***@example.com"`.
  - **SSN patterns**: sequences matching `\d{3}-\d{2}-\d{4}` — replace with `"***-**-****"`.

Give me the complete module in a single file. Use only the Elixir standard library and built-in (`:crypto`, regex) support — no external dependencies.
