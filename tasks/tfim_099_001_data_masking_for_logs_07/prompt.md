# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule LogMaskerTest do
  use ExUnit.Case, async: true

  setup do
    masker = LogMasker.new([:password, :ssn, :credit_card, :token, :secret])
    %{m: masker}
  end

  # -------------------------------------------------------
  # mask/2 — flat maps
  # -------------------------------------------------------

  test "masks sensitive keys in a flat map", %{m: m} do
    result = LogMasker.mask(m, %{username: "alice", password: "s3cr3t"})
    assert result.username == "alice"
    assert result.password == "[MASKED]"
  end

  test "masks string-keyed sensitive fields", %{m: m} do
    result = LogMasker.mask(m, %{"token" => "abc123", "name" => "Bob"})
    assert result["token"] == "[MASKED]"
    assert result["name"] == "Bob"
  end

  test "leaves non-sensitive keys untouched", %{m: m} do
    data = %{user_id: 42, email: "alice@example.com", role: "admin"}
    result = LogMasker.mask(m, data)
    assert result.user_id == 42
    assert result.role == "admin"
  end

  test "masks sensitive keys whose value is a non-string (integer, nil, list)", %{m: m} do
    result = LogMasker.mask(m, %{password: 12345, token: nil, secret: [1, 2, 3]})
    assert result.password == "[MASKED]"
    assert result.token == "[MASKED]"
    assert result.secret == "[MASKED]"
  end

  # -------------------------------------------------------
  # mask/2 — nested maps
  # -------------------------------------------------------

  test "recursively masks nested maps", %{m: m} do
    data = %{
      user: %{
        name: "carol",
        credentials: %{password: "hunter2", token: "tok_xyz"}
      }
    }

    result = LogMasker.mask(m, data)
    assert result.user.name == "carol"
    assert result.user.credentials.password == "[MASKED]"
    assert result.user.credentials.token == "[MASKED]"
  end

  test "handles deeply nested structures", %{m: m} do
    # TODO
  end

  # -------------------------------------------------------
  # mask/2 — lists of maps
  # -------------------------------------------------------

  test "masks sensitive keys in a list of maps", %{m: m} do
    data = [
      %{user: "alice", password: "pass1"},
      %{user: "bob", password: "pass2"}
    ]

    [r1, r2] = LogMasker.mask(m, data)
    assert r1.user == "alice"
    assert r1.password == "[MASKED]"
    assert r2.user == "bob"
    assert r2.password == "[MASKED]"
  end

  test "handles mixed maps containing lists of maps", %{m: m} do
    data = %{
      page: 1,
      results: [
        %{name: "Alice", credit_card: "4111111111111234"},
        %{name: "Bob", credit_card: "5500005555555559"}
      ]
    }

    result = LogMasker.mask(m, data)
    assert result.page == 1
    [r1, r2] = result.results
    assert r1.name == "Alice"
    assert r1.credit_card == "[MASKED]"
    assert r2.name == "Bob"
    assert r2.credit_card == "[MASKED]"
  end

  # -------------------------------------------------------
  # mask/2 — keyword lists
  # -------------------------------------------------------

  test "masks sensitive keys in a keyword list", %{m: m} do
    data = [username: "dave", password: "secret!", role: :viewer]
    result = LogMasker.mask(m, data)
    assert result[:username] == "dave"
    assert result[:password] == "[MASKED]"
    assert result[:role] == :viewer
  end

  # -------------------------------------------------------
  # mask/2 — string values get pattern-masked even on safe keys
  # -------------------------------------------------------

  test "applies pattern masking to string values on non-sensitive keys", %{m: m} do
    data = %{message: "User ssn is 123-45-6789, email: foo@bar.com"}
    result = LogMasker.mask(m, data)
    refute result.message =~ "123-45-6789"
    refute result.message =~ "foo@bar.com"
  end

  # -------------------------------------------------------
  # mask_string/2 — credit card patterns
  # -------------------------------------------------------

  test "masks credit card number (no separators)", %{m: m} do
    result = LogMasker.mask_string(m, "card: 4111111111111234 end")
    refute result =~ "411111111111"
    assert result =~ "1234"
  end

  test "masks credit card number with dashes", %{m: m} do
    result = LogMasker.mask_string(m, "4111-1111-1111-1234")
    assert result == "****-****-****-1234"
  end

  test "masks credit card number with spaces", %{m: m} do
    result = LogMasker.mask_string(m, "4111 1111 1111 1234")
    assert result == "**** **** **** 1234"
  end

  test "last 4 digits of credit card are preserved", %{m: m} do
    result = LogMasker.mask_string(m, "5500005555555559")
    assert String.ends_with?(result, "5559")
    refute result =~ "550000"
  end

  # -------------------------------------------------------
  # mask_string/2 — email patterns
  # -------------------------------------------------------

  test "masks email local part keeping first char", %{m: m} do
    result = LogMasker.mask_string(m, "Contact john.doe@example.com please")
    assert result =~ "j***@example.com"
    refute result =~ "john.doe"
  end

  test "masks multiple emails in one string", %{m: m} do
    result = LogMasker.mask_string(m, "a@b.com and carol@domain.org")
    assert result =~ "a***@b.com"
    assert result =~ "c***@domain.org"
  end

  test "single-char local part email is handled without crashing", %{m: m} do
    result = LogMasker.mask_string(m, "a@b.com")
    assert result =~ "@b.com"
  end

  # -------------------------------------------------------
  # mask_string/2 — SSN patterns
  # -------------------------------------------------------

  test "masks SSN pattern", %{m: m} do
    result = LogMasker.mask_string(m, "SSN: 123-45-6789 on file")
    assert result =~ "***-**-****"
    refute result =~ "123-45-6789"
  end

  test "masks multiple SSNs in one string", %{m: m} do
    result = LogMasker.mask_string(m, "123-45-6789 and 987-65-4321")
    assert result == "***-**-**** and ***-**-****"
  end

  # -------------------------------------------------------
  # mask_string/2 — combined patterns
  # -------------------------------------------------------

  test "masks multiple pattern types in one string", %{m: m} do
    input = "email: user@test.com, ssn: 000-11-2222, card: 4111-1111-1111-9999"
    result = LogMasker.mask_string(m, input)
    refute result =~ "user@test.com"
    refute result =~ "000-11-2222"
    refute result =~ "4111-1111-1111"
    assert result =~ "9999"
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "empty map returns empty map", %{m: m} do
    assert LogMasker.mask(m, %{}) == %{}
  end

  test "empty string returns empty string", %{m: m} do
    assert LogMasker.mask_string(m, "") == ""
  end

  test "string with no sensitive patterns is returned unchanged", %{m: m} do
    plain = "Hello, world! Nothing sensitive here."
    assert LogMasker.mask_string(m, plain) == plain
  end

  test "masker with empty sensitive_keys list masks nothing structurally", %{m: _} do
    empty_masker = LogMasker.new([])
    data = %{password: "visible", token: "also_visible"}
    result = LogMasker.mask(empty_masker, data)
    # Structural keys not masked, but string patterns still apply
    # password value is not a pattern-matched string so it passes through
    assert result.password == "visible"
    assert result.token == "also_visible"
  end

  test "case-insensitive key matching for string keys", %{m: m} do
    result = LogMasker.mask(m, %{"Password" => "secret", "TOKEN" => "abc"})
    assert result["Password"] == "[MASKED]"
    assert result["TOKEN"] == "[MASKED]"
  end
end
```
