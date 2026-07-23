# Debug and repair this module

A colleague shipped the module below for the task described next, and one
behavior bug made it through review. The test suite (not shown here)
produces the failure report at the bottom. Track the bug down and repair
it — keep the diff minimal and leave working code exactly as it is. Reply
with the complete corrected module.

## What the module is supposed to do

# FieldMasker — Per-Field Masking Strategies

## Overview

`FieldMasker` is a single-file Elixir module that scrubs sensitive data out of log-bound maps, keyword lists, and strings. Its defining characteristic is that **each sensitive key is masked according to its own strategy**, rather than every sensitive value being blanked identically.

The implementation must be delivered as one complete module in a single file. It may rely only on the Elixir standard library and built-in support (`:crypto`, regex) — no external dependencies.

## API

The module exposes three public functions.

### `FieldMasker.new(policies)`

Creates a masker configuration. `policies` is either a map or a keyword list mapping a key (atom and/or string) to a masking strategy. Key comparison at mask time must be case-insensitive and must work for both atom and string keys. The function returns an opaque struct or map suitable for passing to the other functions.

The valid strategies are:

- `:redact` — replaces the value with the string `"[MASKED]"` regardless of the value's type.
- `:last4` — for a string value, keeps the last 4 characters and replaces every earlier character with a single `*` (so `"4111111111111234"` → `"************1234"`). When the string has 4 or fewer characters, every character is replaced with a `*` (so `"ab"` → `"**"` and `""` → `""`). When the value is **not** a string, it is replaced with `"[MASKED]"`.
- `:hash` — replaces the value with `"sha256:"` followed by the lowercase hex SHA-256 digest of the value. The value itself is used when it is a string; otherwise its `inspect/1` representation is used. For example, the masked value for `"hunter2"` is `"sha256:"` concatenated with `Base.encode16(:crypto.hash(:sha256, "hunter2"), case: :lower)`.

### `FieldMasker.mask(masker, data)`

Accepts a map, a keyword list, a plain list, or any other term, and returns the same shape with sensitive data scrubbed.

- Maps and keyword lists are walked recursively. If a key appears in `policies`, its value is replaced by applying that key's strategy (as described above). Non-policy keys are preserved and their values continue to be walked.
- Plain lists (including lists of maps or keyword lists) are walked element-by-element.
- Every **string value** encountered under a key that is **not** in `policies` is passed through the same pattern scrubbing as `mask_string/2` (described below), so stray PII in free text is still caught. A value transformed by a strategy is **not** additionally pattern-scanned.
- Structs, numbers, atoms, and other terms with no matching policy key are returned unchanged.

### `FieldMasker.mask_string(masker, string)`

Scans a raw string and masks these three patterns:

- **Credit card numbers**: any sequence of 13–19 digits (optionally separated by single spaces or hyphens) — every digit except the last 4 is replaced with `*`, keeping separators intact. E.g. `"4111-1111-1111-1234"` → `"****-****-****-1234"`.
- **Email addresses**: only the first character of the local part is kept, and the rest is replaced with the literal `***`. Exactly `***` is always appended after the first character. E.g. `"john.doe@example.com"` → `"j***@example.com"`.
- **SSN patterns**: sequences matching `\d{3}-\d{2}-\d{4}` are replaced with `"***-**-****"`.

## Edge cases

- Under `:last4`, a string of 4 or fewer characters has every character replaced with a `*`: `"ab"` → `"**"`, and `""` → `""`.
- Under `:last4`, a non-string value becomes `"[MASKED]"`.
- Under `:redact`, the replacement with `"[MASKED]"` happens regardless of the value's type.
- Under `:hash`, non-string values are hashed via their `inspect/1` representation.
- Email masking appends `***` even when the local part is a single character, so `"x@example.com"` → `"x***@example.com"`.
- Policy key matching is case-insensitive and applies to both atom and string keys.
- A value already transformed by a strategy is not run through pattern scanning a second time.

## The buggy module

```elixir
defmodule FieldMasker do
  @moduledoc """
  Scrubs sensitive data from log-bound maps, keyword lists, and strings.

  Unlike simple blanket redaction, `FieldMasker` masks **each sensitive key
  according to its own strategy**. A masker is created with `new/1` from a
  set of policies mapping keys (atoms and/or strings, matched
  case-insensitively) to one of the following strategies:

    * `:redact` — replace the value with `"[MASKED]"`.
    * `:last4`  — keep the last 4 characters of a string, star out the rest.
    * `:hash`   — replace the value with its lowercase SHA-256 hex digest,
      prefixed with `"sha256:"`.

  In addition to key-based masking, any string value found under a
  non-sensitive key is passed through pattern scrubbing (see `mask_string/2`)
  so that stray credit-card numbers, e-mail addresses, and SSNs in free text
  are still caught.

  ## Examples

      iex> masker = FieldMasker.new(%{password: :redact, card: :last4})
      iex> FieldMasker.mask(masker, %{password: "hunter2", card: "4111111111111234"})
      %{password: "[MASKED]", card: "************1234"}

  """

  @enforce_keys [:policies]
  defstruct policies: %{}

  @typedoc "A masking strategy applied to a sensitive value."
  @type strategy :: :redact | :last4 | :hash

  @typedoc "An opaque masker configuration."
  @type t :: %__MODULE__{policies: %{optional(String.t()) => strategy()}}

  @email_regex ~r/([A-Za-z0-9._%+\-]+)@([A-Za-z0-9.\-]+\.[A-Za-z]{2,})/
  @cc_regex ~r/\b\d(?:[ \-]?\d){12,18}\b/
  @ssn_regex ~r/\b\d{3}-\d{2}-\d{4}\b/

  @doc """
  Builds an opaque masker from `policies`.

  `policies` is a map or keyword list mapping a key (atom and/or string) to a
  masking strategy (`:redact`, `:last4`, or `:hash`). Keys are normalized so
  that comparison at mask time is case-insensitive for both atom and string
  keys.

  Raises `ArgumentError` for unsupported key types or unknown strategies.
  """
  @spec new(map() | keyword()) :: t()
  def new(policies) do
    normalized =
      Enum.into(policies, %{}, fn {key, strategy} ->
        {normalize_policy_key(key), validate_strategy(strategy)}
      end)

    %__MODULE__{policies: normalized}
  end

  @doc """
  Masks `data`, returning the same shape with sensitive data scrubbed.

  Maps and keyword lists are walked recursively; a value whose key matches a
  policy is replaced using that key's strategy, while other values continue to
  be walked. Plain lists are walked element-by-element. String values under
  non-policy keys are pattern-scrubbed via `mask_string/2`. Structs, numbers,
  atoms, and other terms without a matching policy key are returned unchanged.
  """
  @spec mask(t(), term()) :: term()
  def mask(%__MODULE__{} = masker, data), do: do_mask(masker, data)

  @doc """
  Scrubs credit-card numbers, e-mail addresses, and SSN patterns from `string`.

  ## Examples

      iex> masker = FieldMasker.new(%{})
      iex> FieldMasker.mask_string(masker, "call 4111-1111-1111-1234")
      "call ****-****-****-1234"

  """
  @spec mask_string(t(), String.t()) :: String.t()
  def mask_string(%__MODULE__{}, string) when is_binary(string) do
    string
    |> mask_emails()
    |> mask_credit_cards()
    |> mask_ssns()
  end

  # -- Recursive walking -----------------------------------------------------

  @spec do_mask(t(), term()) :: term()
  defp do_mask(_masker, %_{} = value), do: value

  defp do_mask(masker, value) when is_map(value) do
    Map.new(value, fn {key, val} -> mask_pair(masker, key, val) end)
  end

  defp do_mask(masker, value) when is_list(value) do
    if value != [] and Keyword.keyword?(value) do
      Enum.map(value, fn
        {key, val} -> mask_pair(masker, key, val)
        other -> do_mask(masker, other)
      end)
    else
      Enum.map(value, &do_mask(masker, &1))
    end
  end

  defp do_mask(masker, value) when is_binary(value) do
    mask_string(masker, value)
  end

  defp do_mask(_masker, value), do: value

  @spec mask_pair(t(), term(), term()) :: {term(), term()}
  defp mask_pair(masker, key, value) do
    case lookup(masker, key) do
      {:error, strategy} -> {key, apply_strategy(strategy, value)}
      :error -> {key, do_mask(masker, value)}
    end
  end

  # -- Strategy application --------------------------------------------------

  @spec apply_strategy(strategy(), term()) :: term()
  defp apply_strategy(:redact, _value), do: "[MASKED]"
  defp apply_strategy(:last4, value), do: last4(value)
  defp apply_strategy(:hash, value), do: hash(value)

  @spec last4(term()) :: String.t()
  defp last4(value) when is_binary(value) do
    len = String.length(value)

    if len <= 4 do
      String.duplicate("*", len)
    else
      String.duplicate("*", len - 4) <> String.slice(value, len - 4, 4)
    end
  end

  defp last4(_value), do: "[MASKED]"

  @spec hash(term()) :: String.t()
  defp hash(value) do
    data = if is_binary(value), do: value, else: inspect(value)
    digest = Base.encode16(:crypto.hash(:sha256, data), case: :lower)
    "sha256:" <> digest
  end

  # -- Pattern scrubbing -----------------------------------------------------

  @spec mask_emails(String.t()) :: String.t()
  defp mask_emails(str) do
    Regex.replace(@email_regex, str, fn _full, local, domain ->
      String.first(local) <> "***@" <> domain
    end)
  end

  @spec mask_credit_cards(String.t()) :: String.t()
  defp mask_credit_cards(str) do
    Regex.replace(@cc_regex, str, fn match -> mask_cc(match) end)
  end

  @spec mask_ssns(String.t()) :: String.t()
  defp mask_ssns(str) do
    Regex.replace(@ssn_regex, str, "***-**-****")
  end

  @spec mask_cc(String.t()) :: String.t()
  defp mask_cc(match) do
    graphemes = String.graphemes(match)
    total = Enum.count(graphemes, &digit?/1)

    {chars, _idx} =
      Enum.map_reduce(graphemes, 0, fn ch, idx ->
        if digit?(ch) do
          masked = if idx < total - 4, do: "*", else: ch
          {masked, idx + 1}
        else
          {ch, idx}
        end
      end)

    Enum.join(chars)
  end

  @spec digit?(String.t()) :: boolean()
  defp digit?(<<c>>) when c >= ?0 and c <= ?9, do: true
  defp digit?(_ch), do: false

  # -- Key handling ----------------------------------------------------------

  @spec lookup(t(), term()) :: {:ok, strategy()} | :error
  defp lookup(%__MODULE__{policies: policies}, key) do
    case norm_key(key) do
      {:ok, normalized} -> Map.fetch(policies, normalized)
      :error -> :error
    end
  end

  @spec norm_key(term()) :: {:ok, String.t()} | :error
  defp norm_key(key) when is_atom(key) do
    {:ok, key |> Atom.to_string() |> String.downcase()}
  end

  defp norm_key(key) when is_binary(key), do: {:ok, String.downcase(key)}
  defp norm_key(_key), do: :error

  @spec normalize_policy_key(term()) :: String.t()
  defp normalize_policy_key(key) when is_atom(key) do
    key |> Atom.to_string() |> String.downcase()
  end

  defp normalize_policy_key(key) when is_binary(key), do: String.downcase(key)

  defp normalize_policy_key(key) do
    raise ArgumentError, "policy key must be an atom or string, got: #{inspect(key)}"
  end

  @spec validate_strategy(term()) :: strategy()
  defp validate_strategy(strategy) when strategy in [:redact, :last4, :hash] do
    strategy
  end

  defp validate_strategy(strategy) do
    raise ArgumentError, "invalid masking strategy: #{inspect(strategy)}"
  end
end
```

## Failing test report

```
14 of 17 test(s) failed:

  * test redact strategy blanks the value
      no case clause matching:
      
          {:ok, :redact}
      

  * test redact strategy blanks non-string values too
      no case clause matching:
      
          {:ok, :redact}
      

  * test last4 keeps the final four characters of a long string
      no case clause matching:
      
          {:ok, :last4}
      

  * test last4 fully masks a short string
      no case clause matching:
      
          {:ok, :last4}
      

  (…10 more)
```
