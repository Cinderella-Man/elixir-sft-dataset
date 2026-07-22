Implement the private `mask_cc_match/1` function. It receives a single string
`match` — the substring of a credit card number that the `@cc_regex` pattern
matched (13–19 digits, optionally separated by spaces or hyphens). It must return
a masked version of that string where every digit is replaced with `*` **except**
the final four digits, while all separators (spaces and hyphens) are left in place.

Walk the matched span one grapheme at a time. First count how many digits it
contains, and compute a `keep_threshold` equal to that count minus 4 — digits
past this threshold (i.e. the last four) are kept verbatim. Then reduce over the
graphemes: for each digit, track how many digits have been seen so far; if that
running count is greater than `keep_threshold` keep the original digit, otherwise
substitute `"*"`. Non-digit characters (separators) are passed through unchanged.
Reassemble the accumulated characters back into a string in their original order.
For example `"4111-1111-1111-1234"` becomes `"****-****-****-1234"`.

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

  * Credit cards (13–19 digits, optionally separated by spaces or hyphens):
    all digits except the final four are replaced with `*`, separators kept.
  * Emails: the local part keeps only its first character; the rest becomes `***`.
  * SSNs (`\\d{3}-\\d{2}-\\d{4}`): replaced with `***-**-****`.
  """
  @spec mask_string(t(), String.t()) :: String.t()
  def mask_string(%__MODULE__{}, string) when is_binary(string) do
    string
    |> mask_credit_cards()
    |> mask_ssns()
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
    # TODO
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