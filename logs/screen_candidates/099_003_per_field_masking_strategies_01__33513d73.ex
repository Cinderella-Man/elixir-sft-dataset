defmodule FieldMasker do
  @moduledoc """
  Scrubs sensitive data from log-bound maps, keyword lists, and strings.

  Unlike a uniform blanking masker, `FieldMasker` masks **each sensitive key
  with its own strategy**. A masker is built from a policy mapping keys to
  strategies via `new/1`, then applied with `mask/2` (structured data) or
  `mask_string/2` (raw strings).

  ## Strategies

    * `:redact` — replace the value with `"[MASKED]"`, regardless of type.
    * `:last4`  — keep the last 4 characters of a string, masking earlier
      characters with `*`; non-strings become `"[MASKED]"`.
    * `:hash`   — replace the value with `"sha256:"` followed by the lowercase
      hex SHA-256 digest of the value (or of `inspect/1` for non-strings).

  In addition to policy-driven masking, every string value that is *not*
  handled by a strategy is passed through pattern scrubbing (credit cards,
  emails, and SSNs) so that stray PII in free text is still caught.
  """

  @enforce_keys [:policies]
  defstruct policies: %{}

  @typedoc "A supported masking strategy."
  @type strategy :: :redact | :last4 | :hash

  @typedoc "A policy key, given as an atom and/or string."
  @type key :: atom() | String.t()

  @typedoc "An opaque masker configuration."
  @type t :: %__MODULE__{policies: %{optional(String.t()) => strategy()}}

  @cc_regex ~r/\d(?:[ -]?\d){12,18}/
  @ssn_regex ~r/\d{3}-\d{2}-\d{4}/
  @email_regex ~r/([A-Za-z0-9._%+\-]+)@([A-Za-z0-9.\-]+\.[A-Za-z]{2,})/

  @doc """
  Builds a masker from `policies`, a map or keyword list mapping keys to
  strategies.

  Keys may be atoms and/or strings; matching at mask time is case-insensitive
  for both. Raises `ArgumentError` for an unknown strategy.

  ## Examples

      iex> masker = FieldMasker.new(%{"Email" => :hash, password: :redact})
      iex> is_struct(masker, FieldMasker)
      true
  """
  @spec new(map() | keyword()) :: t()
  def new(policies) when is_map(policies) or is_list(policies) do
    normalized =
      Enum.reduce(policies, %{}, fn {k, strategy}, acc ->
        validate_strategy!(strategy)
        Map.put(acc, normalize_key(k), strategy)
      end)

    %__MODULE__{policies: normalized}
  end

  @doc """
  Masks `data`, preserving its shape.

  Maps and keyword lists are walked recursively: policy keys have their values
  replaced by the key's strategy, while other values continue to be walked.
  Plain lists are walked element-by-element. String values not covered by a
  strategy are pattern-scrubbed. Structs, numbers, atoms, and other terms
  without a matching policy are returned unchanged.

  ## Examples

      iex> masker = FieldMasker.new(password: :redact)
      iex> FieldMasker.mask(masker, %{user: "amy", password: "s3cret"})
      %{user: "amy", password: "[MASKED]"}
  """
  @spec mask(t(), term()) :: term()
  def mask(%__MODULE__{} = masker, data), do: do_mask(masker, data)

  @doc """
  Masks credit-card numbers, email addresses, and SSN patterns in a raw
  string.

  ## Examples

      iex> masker = FieldMasker.new([])
      iex> FieldMasker.mask_string(masker, "card 4111-1111-1111-1234")
      "card ****-****-****-1234"
  """
  @spec mask_string(t(), String.t()) :: String.t()
  def mask_string(%__MODULE__{}, string) when is_binary(string) do
    scrub_patterns(string)
  end

  # --- structured walking -------------------------------------------------

  @spec do_mask(t(), term()) :: term()
  defp do_mask(_masker, data) when is_struct(data), do: data

  defp do_mask(masker, data) when is_map(data), do: walk_map(masker, data)

  defp do_mask(masker, data) when is_list(data) do
    if data != [] and Keyword.keyword?(data) do
      walk_keyword(masker, data)
    else
      Enum.map(data, &do_mask(masker, &1))
    end
  end

  defp do_mask(_masker, data) when is_binary(data), do: scrub_patterns(data)

  defp do_mask(_masker, data), do: data

  @spec walk_map(t(), map()) :: map()
  defp walk_map(masker, map) do
    Map.new(map, fn {k, v} -> {k, mask_pair(masker, k, v)} end)
  end

  @spec walk_keyword(t(), keyword()) :: keyword()
  defp walk_keyword(masker, kw) do
    Enum.map(kw, fn {k, v} -> {k, mask_pair(masker, k, v)} end)
  end

  @spec mask_pair(t(), term(), term()) :: term()
  defp mask_pair(masker, key, value) do
    case lookup(masker, key) do
      {:ok, strategy} -> apply_strategy(strategy, value)
      :error -> do_mask(masker, value)
    end
  end

  # --- policy lookup ------------------------------------------------------

  @spec lookup(t(), term()) :: {:ok, strategy()} | :error
  defp lookup(%__MODULE__{policies: policies}, key) do
    case normalize_key(key) do
      nil -> :error
      norm -> Map.fetch(policies, norm)
    end
  end

  @spec normalize_key(term()) :: String.t() | nil
  defp normalize_key(key) when is_atom(key) do
    key |> Atom.to_string() |> String.downcase()
  end

  defp normalize_key(key) when is_binary(key), do: String.downcase(key)
  defp normalize_key(_key), do: nil

  @spec validate_strategy!(term()) :: :ok
  defp validate_strategy!(strategy) when strategy in [:redact, :last4, :hash] do
    :ok
  end

  defp validate_strategy!(strategy) do
    raise ArgumentError, "unknown masking strategy: #{inspect(strategy)}"
  end

  # --- strategies ---------------------------------------------------------

  @spec apply_strategy(strategy(), term()) :: term()
  defp apply_strategy(:redact, _value), do: "[MASKED]"

  defp apply_strategy(:last4, value) when is_binary(value), do: last4(value)
  defp apply_strategy(:last4, _value), do: "[MASKED]"

  defp apply_strategy(:hash, value) do
    data = if is_binary(value), do: value, else: inspect(value)
    digest = :crypto.hash(:sha256, data)
    "sha256:" <> Base.encode16(digest, case: :lower)
  end

  @spec last4(String.t()) :: String.t()
  defp last4(string) do
    len = String.length(string)

    if len <= 4 do
      String.duplicate("*", len)
    else
      String.duplicate("*", len - 4) <> String.slice(string, len - 4, 4)
    end
  end

  # --- pattern scrubbing --------------------------------------------------

  @spec scrub_patterns(String.t()) :: String.t()
  defp scrub_patterns(string) do
    string
    |> scrub_credit_cards()
    |> scrub_ssns()
    |> scrub_emails()
  end

  @spec scrub_credit_cards(String.t()) :: String.t()
  defp scrub_credit_cards(string) do
    Regex.replace(@cc_regex, string, fn match -> mask_cc(match) end)
  end

  @spec mask_cc(String.t()) :: String.t()
  defp mask_cc(match) do
    chars = String.graphemes(match)
    total = Enum.count(chars, &digit?/1)

    {masked, _seen} =
      Enum.map_reduce(chars, 0, fn ch, seen ->
        if digit?(ch) do
          seen = seen + 1
          if seen > total - 4, do: {ch, seen}, else: {"*", seen}
        else
          {ch, seen}
        end
      end)

    Enum.join(masked)
  end

  @spec digit?(String.t()) :: boolean()
  defp digit?(<<c>>) when c in ?0..?9, do: true
  defp digit?(_ch), do: false

  @spec scrub_ssns(String.t()) :: String.t()
  defp scrub_ssns(string) do
    Regex.replace(@ssn_regex, string, "***-**-****")
  end

  @spec scrub_emails(String.t()) :: String.t()
  defp scrub_emails(string) do
    Regex.replace(@email_regex, string, fn _whole, local, domain ->
      first = String.first(local) || ""
      first <> "***@" <> domain
    end)
  end
end