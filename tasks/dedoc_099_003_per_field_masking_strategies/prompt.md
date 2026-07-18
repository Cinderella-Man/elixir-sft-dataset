# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule FieldMasker do
  @enforce_keys [:policies]
  defstruct policies: %{}

  @email_regex ~r/([A-Za-z0-9._%+\-]+)@([A-Za-z0-9.\-]+\.[A-Za-z]{2,})/
  @cc_regex ~r/\b\d(?:[ \-]?\d){12,18}\b/
  @ssn_regex ~r/\b\d{3}-\d{2}-\d{4}\b/

  def new(policies) do
    normalized =
      Enum.into(policies, %{}, fn {key, strategy} ->
        {normalize_policy_key(key), validate_strategy(strategy)}
      end)

    %__MODULE__{policies: normalized}
  end

  def mask(%__MODULE__{} = masker, data), do: do_mask(masker, data)

  def mask_string(%__MODULE__{}, string) when is_binary(string) do
    string
    |> mask_emails()
    |> mask_credit_cards()
    |> mask_ssns()
  end

  # -- Recursive walking -----------------------------------------------------

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

  defp mask_pair(masker, key, value) do
    case lookup(masker, key) do
      {:ok, strategy} -> {key, apply_strategy(strategy, value)}
      :error -> {key, do_mask(masker, value)}
    end
  end

  # -- Strategy application --------------------------------------------------

  defp apply_strategy(:redact, _value), do: "[MASKED]"
  defp apply_strategy(:last4, value), do: last4(value)
  defp apply_strategy(:hash, value), do: hash(value)

  defp last4(value) when is_binary(value) do
    len = String.length(value)

    if len <= 4 do
      String.duplicate("*", len)
    else
      String.duplicate("*", len - 4) <> String.slice(value, len - 4, 4)
    end
  end

  defp last4(_value), do: "[MASKED]"

  defp hash(value) do
    data = if is_binary(value), do: value, else: inspect(value)
    digest = Base.encode16(:crypto.hash(:sha256, data), case: :lower)
    "sha256:" <> digest
  end

  # -- Pattern scrubbing -----------------------------------------------------

  defp mask_emails(str) do
    Regex.replace(@email_regex, str, fn _full, local, domain ->
      String.first(local) <> "***@" <> domain
    end)
  end

  defp mask_credit_cards(str) do
    Regex.replace(@cc_regex, str, fn match -> mask_cc(match) end)
  end

  defp mask_ssns(str) do
    Regex.replace(@ssn_regex, str, "***-**-****")
  end

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

  defp digit?(<<c>>) when c >= ?0 and c <= ?9, do: true
  defp digit?(_ch), do: false

  # -- Key handling ----------------------------------------------------------

  defp lookup(%__MODULE__{policies: policies}, key) do
    case norm_key(key) do
      {:ok, normalized} -> Map.fetch(policies, normalized)
      :error -> :error
    end
  end

  defp norm_key(key) when is_atom(key) do
    {:ok, key |> Atom.to_string() |> String.downcase()}
  end

  defp norm_key(key) when is_binary(key), do: {:ok, String.downcase(key)}
  defp norm_key(_key), do: :error

  defp normalize_policy_key(key) when is_atom(key) do
    key |> Atom.to_string() |> String.downcase()
  end

  defp normalize_policy_key(key) when is_binary(key), do: String.downcase(key)

  defp normalize_policy_key(key) do
    raise ArgumentError, "policy key must be an atom or string, got: #{inspect(key)}"
  end

  defp validate_strategy(strategy) when strategy in [:redact, :last4, :hash] do
    strategy
  end

  defp validate_strategy(strategy) do
    raise ArgumentError, "invalid masking strategy: #{inspect(strategy)}"
  end
end
```
