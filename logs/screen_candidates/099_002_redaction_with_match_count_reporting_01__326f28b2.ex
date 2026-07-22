defmodule LogRedactor do
  @moduledoc """
  Scrub sensitive data from log-bound maps, keyword lists, and strings while
  reporting how much was scrubbed.

  `LogRedactor` behaves like a basic log masker, but every operation returns a
  *redaction report* alongside the scrubbed value so callers can emit metrics
  about how much PII a payload contained.

  A redactor is created with `new/1` and reused across `redact/2` and
  `redact_string/2` calls. Key comparison is case-insensitive and works for both
  atom and string keys. Sensitive keys have their values replaced with the
  string `"[REDACTED]"`; every other string encountered during the walk is
  pattern-scrubbed for credit cards, emails, and SSNs.

  ## Examples

      iex> r = LogRedactor.new([:password])
      iex> LogRedactor.redact(r, %{password: "secret", note: "x"})
      {%{password: "[REDACTED]", note: "x"},
       %{keys_masked: 1, credit_cards: 0, emails: 0, ssns: 0}}

  """

  @enforce_keys [:keys]
  defstruct keys: MapSet.new()

  @type t :: %__MODULE__{keys: MapSet.t(String.t())}

  @typedoc "A redaction report with exactly four counters."
  @type report :: %{
          keys_masked: non_neg_integer(),
          credit_cards: non_neg_integer(),
          emails: non_neg_integer(),
          ssns: non_neg_integer()
        }

  # 13-19 digits, optionally separated by single spaces or hyphens.
  @cc_regex ~r/(?<!\d)\d(?:[ -]?\d){12,18}(?!\d)/
  @ssn_regex ~r/\d{3}-\d{2}-\d{4}/
  @email_regex ~r/([A-Za-z0-9._%+-]+)@([A-Za-z0-9.-]+\.[A-Za-z]{2,})/

  @doc """
  Create a redactor configuration from a list of sensitive keys.

  `sensitive_keys` is a list of atoms and/or strings (e.g. `[:password, "ssn"]`).
  Keys are normalized to downcased strings so that comparison at redaction time
  is case-insensitive across both atom and string keys.
  """
  @spec new([atom() | String.t()]) :: t()
  def new(sensitive_keys) when is_list(sensitive_keys) do
    keys =
      sensitive_keys
      |> Enum.map(&normalize_key/1)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    %__MODULE__{keys: keys}
  end

  @doc """
  Redact `data`, returning `{scrubbed, report}`.

  Maps and keyword lists are walked recursively: a value whose key matches a
  sensitive key becomes `"[REDACTED]"`, otherwise the value is walked. Plain
  lists are walked element-by-element. Every string encountered under a
  non-sensitive key is pattern-scrubbed. Structs, numbers, atoms, and other
  terms are returned unchanged.
  """
  @spec redact(t(), term()) :: {term(), report()}
  def redact(%__MODULE__{} = redactor, data) do
    walk(data, redactor, empty_report())
  end

  @doc """
  Scrub the three PII patterns from a raw `string`, returning
  `{scrubbed_string, report}`.

  Credit-card numbers keep only their last four digits, emails keep only the
  first character of the local part, and SSNs become `"***-**-****"`. The
  report's `:keys_masked` is always `0`; the other counters report how many
  matches of each pattern were masked.
  """
  @spec redact_string(t(), String.t()) :: {String.t(), report()}
  def redact_string(%__MODULE__{} = _redactor, string) when is_binary(string) do
    {scrubbed, counts} = scan_string(string)
    {scrubbed, Map.merge(empty_report(), counts)}
  end

  # --- Recursive walk -------------------------------------------------------

  @spec walk(term(), t(), report()) :: {term(), report()}
  defp walk(data, _redactor, rep) when is_struct(data), do: {data, rep}

  defp walk(data, redactor, rep) when is_map(data) do
    Enum.reduce(data, {%{}, rep}, fn {key, value}, {acc, r} ->
      {new_value, new_rep} = redact_pair(key, value, redactor, r)
      {Map.put(acc, key, new_value), new_rep}
    end)
  end

  defp walk(data, redactor, rep) when is_list(data) do
    if Keyword.keyword?(data) do
      Enum.map_reduce(data, rep, fn {key, value}, r ->
        {new_value, new_rep} = redact_pair(key, value, redactor, r)
        {{key, new_value}, new_rep}
      end)
    else
      Enum.map_reduce(data, rep, fn element, r -> walk(element, redactor, r) end)
    end
  end

  defp walk(data, _redactor, rep) when is_binary(data) do
    {scrubbed, counts} = scan_string(data)
    {scrubbed, merge_counts(rep, counts)}
  end

  defp walk(data, _redactor, rep), do: {data, rep}

  @spec redact_pair(term(), term(), t(), report()) :: {term(), report()}
  defp redact_pair(key, value, redactor, rep) do
    if sensitive?(key, redactor) do
      {"[REDACTED]", %{rep | keys_masked: rep.keys_masked + 1}}
    else
      walk(value, redactor, rep)
    end
  end

  # --- Key helpers ----------------------------------------------------------

  @spec sensitive?(term(), t()) :: boolean()
  defp sensitive?(key, %__MODULE__{keys: keys}) do
    case normalize_key(key) do
      nil -> false
      normalized -> MapSet.member?(keys, normalized)
    end
  end

  @spec normalize_key(term()) :: String.t() | nil
  defp normalize_key(key) when is_atom(key), do: key |> Atom.to_string() |> String.downcase()
  defp normalize_key(key) when is_binary(key), do: String.downcase(key)
  defp normalize_key(_key), do: nil

  # --- String scanning ------------------------------------------------------

  @spec scan_string(String.t()) :: {String.t(), map()}
  defp scan_string(str) do
    {after_cc, cards} = mask_credit_cards(str)
    {after_ssn, ssns} = mask_ssns(after_cc)
    {after_email, emails} = mask_emails(after_ssn)
    {after_email, %{credit_cards: cards, emails: emails, ssns: ssns}}
  end

  @spec mask_credit_cards(String.t()) :: {String.t(), non_neg_integer()}
  defp mask_credit_cards(str) do
    count = length(Regex.scan(@cc_regex, str))
    scrubbed = Regex.replace(@cc_regex, str, fn match -> mask_cc_match(match) end)
    {scrubbed, count}
  end

  @spec mask_ssns(String.t()) :: {String.t(), non_neg_integer()}
  defp mask_ssns(str) do
    count = length(Regex.scan(@ssn_regex, str))
    scrubbed = Regex.replace(@ssn_regex, str, "***-**-****")
    {scrubbed, count}
  end

  @spec mask_emails(String.t()) :: {String.t(), non_neg_integer()}
  defp mask_emails(str) do
    count = length(Regex.scan(@email_regex, str))

    scrubbed =
      Regex.replace(@email_regex, str, fn _match, local, domain ->
        String.first(local) <> "***@" <> domain
      end)

    {scrubbed, count}
  end

  @spec mask_cc_match(String.t()) :: String.t()
  defp mask_cc_match(match) do
    mask_n = max(count_digits(match) - 4, 0)

    {chars, _seen} =
      match
      |> String.to_charlist()
      |> Enum.map_reduce(0, fn char, seen ->
        if char in ?0..?9 do
          seen = seen + 1
          if seen <= mask_n, do: {?*, seen}, else: {char, seen}
        else
          {char, seen}
        end
      end)

    List.to_string(chars)
  end

  @spec count_digits(String.t()) :: non_neg_integer()
  defp count_digits(str) do
    str |> String.to_charlist() |> Enum.count(&(&1 in ?0..?9))
  end

  # --- Report helpers -------------------------------------------------------

  @spec empty_report() :: report()
  defp empty_report, do: %{keys_masked: 0, credit_cards: 0, emails: 0, ssns: 0}

  @spec merge_counts(report(), map()) :: report()
  defp merge_counts(rep, counts) do
    %{
      rep
      | credit_cards: rep.credit_cards + counts.credit_cards,
        emails: rep.emails + counts.emails,
        ssns: rep.ssns + counts.ssns
    }
  end
end