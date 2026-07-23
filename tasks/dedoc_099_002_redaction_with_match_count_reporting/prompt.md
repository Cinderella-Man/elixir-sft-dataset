# Add moduledoc, docs, and specs

Below: a correct, tested, undocumented module. Deliver the same module
fully documented — a `@moduledoc`, a per-public-function `@doc` and
`@spec`, and supporting `@type`s where useful. Behavior, names, structure:
unchanged. One file.

## The module

```elixir
defmodule LogRedactor do
  @enforce_keys [:keys]
  defstruct keys: MapSet.new()

  @empty_report %{keys_masked: 0, credit_cards: 0, emails: 0, ssns: 0}

  # 13-19 digits, optionally separated by single spaces or hyphens.
  @cc_regex ~r/\d(?:[ -]?\d){12,18}/

  @ssn_regex ~r/\d{3}-\d{2}-\d{4}/

  @email_regex ~r/([A-Za-z0-9._%+\-]+)@([A-Za-z0-9.\-]+\.[A-Za-z]{2,})/

  def new(sensitive_keys) when is_list(sensitive_keys) do
    set =
      sensitive_keys
      |> Enum.map(&normalize_key/1)
      |> MapSet.new()

    %__MODULE__{keys: set}
  end

  def redact(%__MODULE__{} = redactor, data), do: walk(redactor, data)

  def redact_string(%__MODULE__{} = _redactor, string) when is_binary(string) do
    scrub_string(string)
  end

  # --- Recursive walk -------------------------------------------------------

  defp walk(redactor, data) do
    cond do
      is_struct(data) -> {data, @empty_report}
      is_map(data) -> walk_map(redactor, data)
      is_list(data) -> walk_any_list(redactor, data)
      is_binary(data) -> scrub_string(data)
      true -> {data, @empty_report}
    end
  end

  defp walk_any_list(redactor, list) do
    if Keyword.keyword?(list) and list != [] do
      walk_keyword(redactor, list)
    else
      walk_list(redactor, list)
    end
  end

  defp walk_map(redactor, map) do
    Enum.reduce(map, {%{}, @empty_report}, fn {k, v}, {acc, rep} ->
      {new_v, new_rep} = redact_pair(redactor, k, v)
      {Map.put(acc, k, new_v), merge(rep, new_rep)}
    end)
  end

  defp walk_keyword(redactor, kw) do
    {acc, rep} =
      Enum.reduce(kw, {[], @empty_report}, fn {k, v}, {acc, rep} ->
        {new_v, new_rep} = redact_pair(redactor, k, v)
        {[{k, new_v} | acc], merge(rep, new_rep)}
      end)

    {Enum.reverse(acc), rep}
  end

  defp walk_list(redactor, list) do
    {acc, rep} =
      Enum.reduce(list, {[], @empty_report}, fn el, {acc, rep} ->
        {new_el, new_rep} = walk(redactor, el)
        {[new_el | acc], merge(rep, new_rep)}
      end)

    {Enum.reverse(acc), rep}
  end

  defp redact_pair(redactor, key, value) do
    if sensitive?(redactor, key) do
      {"[REDACTED]", %{@empty_report | keys_masked: 1}}
    else
      walk(redactor, value)
    end
  end

  # --- String scrubbing -----------------------------------------------------

  defp scrub_string(string) do
    {s1, cards} = mask_credit_cards(string)
    {s2, ssns} = mask_ssns(s1)
    {s3, emails} = mask_emails(s2)

    {s3, %{keys_masked: 0, credit_cards: cards, emails: emails, ssns: ssns}}
  end

  defp mask_credit_cards(string) do
    count = length(Regex.scan(@cc_regex, string))
    scrubbed = Regex.replace(@cc_regex, string, &mask_cc_match/1)
    {scrubbed, count}
  end

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

  defp mask_ssns(string) do
    count = length(Regex.scan(@ssn_regex, string))
    {Regex.replace(@ssn_regex, string, "***-**-****"), count}
  end

  defp mask_emails(string) do
    count = length(Regex.scan(@email_regex, string))

    scrubbed =
      Regex.replace(@email_regex, string, fn _full, local, domain ->
        "#{String.first(local)}***@#{domain}"
      end)

    {scrubbed, count}
  end

  # --- Key helpers ----------------------------------------------------------

  defp sensitive?(redactor, key) do
    case key_string(key) do
      nil -> false
      norm -> MapSet.member?(redactor.keys, norm)
    end
  end

  defp normalize_key(key) when is_atom(key), do: key |> Atom.to_string() |> String.downcase()
  defp normalize_key(key) when is_binary(key), do: String.downcase(key)

  defp key_string(key) when is_atom(key), do: key |> Atom.to_string() |> String.downcase()
  defp key_string(key) when is_binary(key), do: String.downcase(key)
  defp key_string(_key), do: nil

  defp merge(a, b), do: Map.merge(a, b, fn _k, v1, v2 -> v1 + v2 end)
end
```
