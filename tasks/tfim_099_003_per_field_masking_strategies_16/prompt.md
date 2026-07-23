# Complete the blanked test

You get a module and its ExUnit harness, minus the body of ONE `test` —
the `# TODO` marks the spot, and its name says what it must prove. Write
exactly that test so the harness passes against a correct implementation
of the module.

## Module under test

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
      {:ok, strategy} -> {key, apply_strategy(strategy, value)}
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

## Test harness — implement the `# TODO` test

```elixir
defmodule FieldMaskerTest do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # Strategy: :redact
  # -------------------------------------------------------

  test "redact strategy blanks the value" do
    m = FieldMasker.new(%{password: :redact})
    result = FieldMasker.mask(m, %{password: "hunter2", user: "alice"})
    assert result.password == "[MASKED]"
    assert result.user == "alice"
  end

  test "redact strategy blanks non-string values too" do
    m = FieldMasker.new(%{token: :redact})
    result = FieldMasker.mask(m, %{token: 12345})
    assert result.token == "[MASKED]"
  end

  # -------------------------------------------------------
  # Strategy: :last4
  # -------------------------------------------------------

  test "last4 keeps the final four characters of a long string" do
    m = FieldMasker.new(%{card: :last4})
    result = FieldMasker.mask(m, %{card: "4111111111111234"})
    assert result.card == "************1234"
  end

  test "last4 fully masks a short string" do
    m = FieldMasker.new(%{pin: :last4})
    result = FieldMasker.mask(m, %{pin: "ab"})
    assert result.pin == "**"
  end

  test "last4 leaves an empty string empty" do
    m = FieldMasker.new(%{code: :last4})
    result = FieldMasker.mask(m, %{code: ""})
    assert result.code == ""
  end

  test "last4 on a non-string value falls back to [MASKED]" do
    m = FieldMasker.new(%{card: :last4})
    result = FieldMasker.mask(m, %{card: 42})
    assert result.card == "[MASKED]"
  end

  # -------------------------------------------------------
  # Strategy: :hash
  # -------------------------------------------------------

  test "hash strategy produces a deterministic sha256 hex digest" do
    m = FieldMasker.new(%{password: :hash})
    result = FieldMasker.mask(m, %{password: "hunter2"})
    expected = "sha256:" <> Base.encode16(:crypto.hash(:sha256, "hunter2"), case: :lower)
    assert result.password == expected
  end

  test "hash strategy is stable across calls" do
    m = FieldMasker.new(%{password: :hash})
    a = FieldMasker.mask(m, %{password: "same"})
    b = FieldMasker.mask(m, %{password: "same"})
    assert a.password == b.password
  end

  # -------------------------------------------------------
  # Non-policy keys: pattern scrubbing still applies
  # -------------------------------------------------------

  test "string values under non-policy keys get pattern-masked" do
    m = FieldMasker.new(%{password: :redact})
    result = FieldMasker.mask(m, %{note: "reach me at john.doe@example.com"})
    assert result.note =~ "j***@example.com"
    refute result.note =~ "john.doe"
  end

  test "non-policy non-string values are untouched" do
    m = FieldMasker.new(%{password: :redact})
    result = FieldMasker.mask(m, %{count: 7, active: true})
    assert result.count == 7
    assert result.active == true
  end

  test "a strategy-transformed value is not additionally pattern-scanned" do
    # value looks like an SSN but :redact wins wholesale
    m = FieldMasker.new(%{ssn: :redact})
    result = FieldMasker.mask(m, %{ssn: "123-45-6789"})
    assert result.ssn == "[MASKED]"
  end

  test "hash digests the raw value, not a pattern-scrubbed rewrite of it" do
    # The strategy sees the original "123-45-6789"; had the SSN pattern been
    # scrubbed to "***-**-****" first, the digest would differ.
    m = FieldMasker.new(%{ssn: :hash})
    result = FieldMasker.mask(m, %{ssn: "123-45-6789"})
    expected = "sha256:" <> Base.encode16(:crypto.hash(:sha256, "123-45-6789"), case: :lower)
    assert result.ssn == expected
  end

  test "hash digests a raw e-mail value rather than its pattern-masked form" do
    m = FieldMasker.new(%{contact: :hash})
    result = FieldMasker.mask(m, %{contact: "john.doe@example.com"})

    expected =
      "sha256:" <> Base.encode16(:crypto.hash(:sha256, "john.doe@example.com"), case: :lower)

    assert result.contact == expected
  end

  test "last4 keeps the raw final four digits of an SSN-shaped value" do
    # Scrubbing first would yield "***-**-****", whose last four characters
    # are stars; the strategy must operate on the untouched value.
    m = FieldMasker.new(%{ssn: :last4})
    result = FieldMasker.mask(m, %{ssn: "123-45-6789"})
    assert result.ssn == "*******6789"
  end

  # -------------------------------------------------------
  # Structure / config handling
  # -------------------------------------------------------

  test "different keys can use different strategies" do
    m = FieldMasker.new(%{password: :redact, card: :last4})
    result = FieldMasker.mask(m, %{password: "x", card: "5500005555555559"})
    assert result.password == "[MASKED]"
    assert result.card == "************5559"
  end

  test "recursively applies strategies in nested maps" do
    m = FieldMasker.new(%{password: :redact})
    result = FieldMasker.mask(m, %{user: %{name: "carol", password: "deep"}})
    assert result.user.name == "carol"
    assert result.user.password == "[MASKED]"
  end

  test "applies strategies in keyword lists" do
    m = FieldMasker.new(%{password: :redact})
    result = FieldMasker.mask(m, username: "dave", password: "secret!")
    assert result[:username] == "dave"
    assert result[:password] == "[MASKED]"
  end

  test "policy keys match case-insensitively for string keys" do
    # TODO
  end

  test "policies given as a keyword list work the same" do
    m = FieldMasker.new(password: :redact, card: :last4)
    result = FieldMasker.mask(m, %{password: "x", card: "4111111111111234"})
    assert result.password == "[MASKED]"
    assert result.card == "************1234"
  end

  test "mask_string masks a dashed credit card" do
    m = FieldMasker.new(%{})
    assert FieldMasker.mask_string(m, "4111-1111-1111-1234") == "****-****-****-1234"
  end

  test "hash strategy hashes the inspect representation of a non-string value" do
    m = FieldMasker.new(%{password: :hash})
    result = FieldMasker.mask(m, %{password: :secret})
    expected = "sha256:" <> Base.encode16(:crypto.hash(:sha256, inspect(:secret)), case: :lower)
    assert result.password == expected
  end

  test "mask_string replaces a bare SSN pattern in free text" do
    m = FieldMasker.new(%{})
    assert FieldMasker.mask_string(m, "ssn 123-45-6789 ok") == "ssn ***-**-**** ok"
  end

  test "plain lists of maps and keyword lists are walked element-by-element" do
    m = FieldMasker.new(%{password: :redact})
    data = [%{password: "a"}, [password: "b"], "ping x@example.com"]
    result = FieldMasker.mask(m, data)
    assert [%{password: "[MASKED]"}, [password: "[MASKED]"], "ping x***@example.com"] = result
  end

  test "a struct value under a non-policy key is returned unchanged" do
    m = FieldMasker.new(%{password: :redact})
    uri = URI.parse("mailto:john.doe@example.com")
    result = FieldMasker.mask(m, %{contact: uri})
    assert result.contact == uri
  end

  test "a differently-cased string policy key masks an atom data key" do
    m = FieldMasker.new(%{"PassWord" => :redact})
    result = FieldMasker.mask(m, %{password: "x"})
    assert result.password == "[MASKED]"
  end

  test "mask_string masks a bare 13-digit card and a space-separated 19-digit card" do
    m = FieldMasker.new(%{})
    assert FieldMasker.mask_string(m, "4111111111234") == "*********1234"
    # 19 digits: only the final four digits (1, 2, 3, 4) survive, separators kept intact.
    assert FieldMasker.mask_string(m, "4111 1111 1111 1111 234") == "**** **** **** ***1 234"
  end
end
```
