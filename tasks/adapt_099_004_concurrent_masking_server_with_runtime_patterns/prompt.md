# Rework this solution for a changed brief

The module below is a complete, tested solution to a neighboring task. Treat
it as your starting codebase, not as a suggestion — carry over what still
fits and rewrite what the new brief demands. Where old code and the new
specification conflict (module name, public API, behavior, constraints,
output format), the new specification is authoritative. Return the complete
final result.

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

I'm about to wire log scrubbing into our pipeline and I need a module from you first — call it `MaskingServer`. It should be a `GenServer` that scrubs sensitive data out of log-bound maps, keyword lists, and strings on behalf of concurrent callers, lets me register **extra masking patterns at runtime**, and keeps a running tally of cumulative masking statistics.

Here's the public API I'm going to call against.

`MaskingServer.start_link(opts)` starts the server. `opts` is a keyword list, and `opts[:sensitive_keys]` is a list of atoms and/or strings, defaulting to `[]` when it isn't there. When masking, key comparison has to be case-insensitive, and it has to work for both atom keys and string keys. It returns `{:ok, pid}`.

`MaskingServer.mask(server, data)` is a synchronous call. I'll hand it a map, a keyword list, a plain list, or any other term, and I expect the same shape back with the sensitive data scrubbed. Maps and keyword lists get walked recursively: if a key matches one of the configured sensitive keys, its value is replaced with `"[MASKED]"` no matter what type that value is; non-sensitive keys are preserved and their values keep getting walked. Plain lists — including lists of maps or lists of keyword lists — get walked element by element. Every **string value** you hit under a non-sensitive key goes through exactly the same pattern scrubbing as `mask_string/2`. Values that were replaced with `"[MASKED]"` because of a sensitive key must **not** be pattern-scanned on top of that. Structs, numbers, atoms, and anything else come back unchanged.

`MaskingServer.mask_string(server, string)` is also a synchronous call: it scans a raw string, masks the built-in patterns plus whatever custom patterns have been registered (see `add_pattern/3`), and returns the scrubbed string. The built-in ones I need are credit card numbers — any sequence of 13–19 digits, optionally separated by single spaces or hyphens, where every digit except the last 4 becomes `*` and the separators stay intact, so `"4111-1111-1111-1234"` comes back as `"****-****-****-1234"`; email addresses — keep only the first character of the local part and replace the rest with `***`, so `"john.doe@example.com"` becomes `"j***@example.com"`; and SSN patterns — anything matching `\d{3}-\d{2}-\d{4}` gets replaced with `"***-**-****"`.

`MaskingServer.add_pattern(server, regex, replacement)` registers an additional masking pattern, where `regex` is a compiled `Regex` and `replacement` is a string. It returns `:ok`. Ordering matters to me: when a string is scrubbed, the built-in patterns run first (credit cards, then SSNs, then emails), and after that every registered custom pattern is applied in the order it was added, each one via a standard regex replace with its replacement string. Registered patterns apply to every string scrubbed from then on, by both `mask_string/2` and `mask/2`.

`MaskingServer.stats(server)` returns a map `%{keys_masked: k, patterns_applied: p}` covering cumulative work since the server started. `:keys_masked` is the total number of values replaced with `"[MASKED]"` because their key was sensitive, summed across every `mask/2` call. `:patterns_applied` is the total number of pattern matches replaced — built-in **and** custom patterns — across every string scrubbed by every `mask/2` and `mask_string/2` call.

Since every operation goes through the `GenServer`, concurrent callers end up serialized and the statistics stay exact under concurrency, which is the property I care about most here.

Send me the complete module in a single file, please. Elixir standard library and built-in regex support only — no external dependencies.
