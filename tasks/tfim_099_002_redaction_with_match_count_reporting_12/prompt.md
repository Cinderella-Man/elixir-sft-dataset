# Complete the blanked test

You get a module and its ExUnit harness, minus the body of ONE `test` —
the `# TODO` marks the spot, and its name says what it must prove. Write
exactly that test so the harness passes against a correct implementation
of the module.

## Module under test

```elixir
defmodule LogRedactor do
  @moduledoc """
  Scrubs sensitive data from log-bound maps, keyword lists, plain lists, and
  strings while reporting how much was scrubbed.

  Every public operation returns a `{scrubbed, report}` tuple so callers can
  emit metrics about how much PII a payload contained. Redaction happens in
  two ways:

    * **Sensitive keys** — values whose key matches a configured sensitive key
      (case-insensitively, for atom or string keys) are replaced with the
      string `"[REDACTED]"`.
    * **Pattern scrubbing** — every string encountered under a non-sensitive
      key (and any raw string passed to `redact_string/2`) is scanned for
      credit-card numbers, email addresses, and SSNs, which are masked in
      place.

  The report is always a map with exactly the keys `:keys_masked`,
  `:credit_cards`, `:emails`, and `:ssns`.
  """

  @enforce_keys [:keys]
  defstruct keys: MapSet.new()

  @type t :: %__MODULE__{keys: MapSet.t()}

  @type report :: %{
          keys_masked: non_neg_integer(),
          credit_cards: non_neg_integer(),
          emails: non_neg_integer(),
          ssns: non_neg_integer()
        }

  @empty_report %{keys_masked: 0, credit_cards: 0, emails: 0, ssns: 0}

  # 13-19 digits, optionally separated by single spaces or hyphens.
  @cc_regex ~r/\d(?:[ -]?\d){12,18}/

  @ssn_regex ~r/\d{3}-\d{2}-\d{4}/

  @email_regex ~r/([A-Za-z0-9._%+\-]+)@([A-Za-z0-9.\-]+\.[A-Za-z]{2,})/

  @doc """
  Builds an opaque redactor configuration from a list of sensitive keys.

  `sensitive_keys` may contain atoms and/or strings. Comparisons performed at
  redaction time are case-insensitive and match both atom and string keys.
  """
  @spec new([atom() | String.t()]) :: t()
  def new(sensitive_keys) when is_list(sensitive_keys) do
    set =
      sensitive_keys
      |> Enum.map(&normalize_key/1)
      |> MapSet.new()

    %__MODULE__{keys: set}
  end

  @doc """
  Redacts `data`, returning `{scrubbed, report}`.

  Maps and keyword lists are walked recursively; plain lists are walked
  element-by-element. Sensitive keys have their values replaced with
  `"[REDACTED]"`, while every other string is pattern-scrubbed. Structs,
  numbers, atoms, and other terms are returned unchanged.
  """
  @spec redact(t(), term()) :: {term(), report()}
  def redact(%__MODULE__{} = redactor, data), do: walk(redactor, data)

  @doc """
  Scrubs the three sensitive patterns (credit cards, emails, SSNs) from a raw
  string and returns `{scrubbed_string, report}`.

  `:keys_masked` is always `0` for this function; the other three counters
  report how many matches of each pattern were masked.
  """
  @spec redact_string(t(), String.t()) :: {String.t(), report()}
  def redact_string(%__MODULE__{} = _redactor, string) when is_binary(string) do
    scrub_string(string)
  end

  # --- Recursive walk -------------------------------------------------------

  @spec walk(t(), term()) :: {term(), report()}
  defp walk(redactor, data) do
    cond do
      is_struct(data) -> {data, @empty_report}
      is_map(data) -> walk_map(redactor, data)
      is_list(data) -> walk_any_list(redactor, data)
      is_binary(data) -> scrub_string(data)
      true -> {data, @empty_report}
    end
  end

  @spec walk_any_list(t(), list()) :: {list(), report()}
  defp walk_any_list(redactor, list) do
    if Keyword.keyword?(list) and list != [] do
      walk_keyword(redactor, list)
    else
      walk_list(redactor, list)
    end
  end

  @spec walk_map(t(), map()) :: {map(), report()}
  defp walk_map(redactor, map) do
    Enum.reduce(map, {%{}, @empty_report}, fn {k, v}, {acc, rep} ->
      {new_v, new_rep} = redact_pair(redactor, k, v)
      {Map.put(acc, k, new_v), merge(rep, new_rep)}
    end)
  end

  @spec walk_keyword(t(), keyword()) :: {keyword(), report()}
  defp walk_keyword(redactor, kw) do
    {acc, rep} =
      Enum.reduce(kw, {[], @empty_report}, fn {k, v}, {acc, rep} ->
        {new_v, new_rep} = redact_pair(redactor, k, v)
        {[{k, new_v} | acc], merge(rep, new_rep)}
      end)

    {Enum.reverse(acc), rep}
  end

  @spec walk_list(t(), list()) :: {list(), report()}
  defp walk_list(redactor, list) do
    {acc, rep} =
      Enum.reduce(list, {[], @empty_report}, fn el, {acc, rep} ->
        {new_el, new_rep} = walk(redactor, el)
        {[new_el | acc], merge(rep, new_rep)}
      end)

    {Enum.reverse(acc), rep}
  end

  @spec redact_pair(t(), term(), term()) :: {term(), report()}
  defp redact_pair(redactor, key, value) do
    if sensitive?(redactor, key) do
      {"[REDACTED]", %{@empty_report | keys_masked: 1}}
    else
      walk(redactor, value)
    end
  end

  # --- String scrubbing -----------------------------------------------------

  @spec scrub_string(String.t()) :: {String.t(), report()}
  defp scrub_string(string) do
    {s1, cards} = mask_credit_cards(string)
    {s2, ssns} = mask_ssns(s1)
    {s3, emails} = mask_emails(s2)

    {s3, %{keys_masked: 0, credit_cards: cards, emails: emails, ssns: ssns}}
  end

  @spec mask_credit_cards(String.t()) :: {String.t(), non_neg_integer()}
  defp mask_credit_cards(string) do
    count = length(Regex.scan(@cc_regex, string))
    scrubbed = Regex.replace(@cc_regex, string, &mask_cc_match/1)
    {scrubbed, count}
  end

  @spec mask_cc_match(String.t()) :: String.t()
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

  @spec mask_ssns(String.t()) :: {String.t(), non_neg_integer()}
  defp mask_ssns(string) do
    count = length(Regex.scan(@ssn_regex, string))
    {Regex.replace(@ssn_regex, string, "***-**-****"), count}
  end

  @spec mask_emails(String.t()) :: {String.t(), non_neg_integer()}
  defp mask_emails(string) do
    count = length(Regex.scan(@email_regex, string))

    scrubbed =
      Regex.replace(@email_regex, string, fn _full, local, domain ->
        "#{String.first(local)}***@#{domain}"
      end)

    {scrubbed, count}
  end

  # --- Key helpers ----------------------------------------------------------

  @spec sensitive?(t(), term()) :: boolean()
  defp sensitive?(redactor, key) do
    case key_string(key) do
      nil -> false
      norm -> MapSet.member?(redactor.keys, norm)
    end
  end

  @spec normalize_key(atom() | String.t()) :: String.t()
  defp normalize_key(key) when is_atom(key), do: key |> Atom.to_string() |> String.downcase()
  defp normalize_key(key) when is_binary(key), do: String.downcase(key)

  @spec key_string(term()) :: String.t() | nil
  defp key_string(key) when is_atom(key), do: key |> Atom.to_string() |> String.downcase()
  defp key_string(key) when is_binary(key), do: String.downcase(key)
  defp key_string(_key), do: nil

  @spec merge(report(), report()) :: report()
  defp merge(a, b), do: Map.merge(a, b, fn _k, v1, v2 -> v1 + v2 end)
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule LogRedactorStructFixture do
  @moduledoc false
  defstruct [:name, :password, :note]
end

defmodule LogRedactorTest do
  use ExUnit.Case, async: false

  setup do
    r = LogRedactor.new([:password, :ssn, :token, :secret, :credit_card])
    %{r: r}
  end

  # -------------------------------------------------------
  # redact/2 — structural masking + keys_masked report
  # -------------------------------------------------------

  test "masks sensitive keys and reports keys_masked", %{r: r} do
    {scrubbed, report} = LogRedactor.redact(r, %{username: "alice", password: "s3cr3t"})
    assert scrubbed.username == "alice"
    assert scrubbed.password == "[REDACTED]"
    assert report.keys_masked == 1
  end

  test "masks sensitive keys regardless of value type", %{r: r} do
    {scrubbed, report} = LogRedactor.redact(r, %{password: 12345, token: nil, secret: [1, 2, 3]})
    assert scrubbed.password == "[REDACTED]"
    assert scrubbed.token == "[REDACTED]"
    assert scrubbed.secret == "[REDACTED]"
    assert report.keys_masked == 3
  end

  test "leaves non-sensitive keys untouched", %{r: r} do
    {scrubbed, report} = LogRedactor.redact(r, %{user_id: 42, role: "admin"})
    assert scrubbed.user_id == 42
    assert scrubbed.role == "admin"
    assert report.keys_masked == 0
  end

  test "case-insensitive matching for string keys", %{r: r} do
    {scrubbed, report} = LogRedactor.redact(r, %{"Password" => "x", "TOKEN" => "y"})
    assert scrubbed["Password"] == "[REDACTED]"
    assert scrubbed["TOKEN"] == "[REDACTED]"
    assert report.keys_masked == 2
  end

  test "recursively counts keys_masked in nested maps", %{r: r} do
    data = %{user: %{name: "carol", creds: %{password: "hunter2", token: "tok"}}}
    {scrubbed, report} = LogRedactor.redact(r, data)
    assert scrubbed.user.name == "carol"
    assert scrubbed.user.creds.password == "[REDACTED]"
    assert scrubbed.user.creds.token == "[REDACTED]"
    assert report.keys_masked == 2
  end

  test "counts keys_masked across a list of maps", %{r: r} do
    data = [%{user: "a", password: "1"}, %{user: "b", password: "2"}]
    {scrubbed, report} = LogRedactor.redact(r, data)
    [m1, m2] = scrubbed
    assert m1.password == "[REDACTED]"
    assert m2.password == "[REDACTED]"
    assert report.keys_masked == 2
  end

  test "masks sensitive keys in a keyword list", %{r: r} do
    {scrubbed, report} =
      LogRedactor.redact(r, username: "dave", password: "secret!", role: :viewer)

    assert scrubbed[:username] == "dave"
    assert scrubbed[:password] == "[REDACTED]"
    assert scrubbed[:role] == :viewer
    assert report.keys_masked == 1
  end

  # -------------------------------------------------------
  # redact/2 — pattern scrubbing on string values
  # -------------------------------------------------------

  test "pattern-masks string values under non-sensitive keys and counts them", %{r: r} do
    data = %{message: "ssn 123-45-6789 email a@b.com card 4111-1111-1111-1234"}
    {scrubbed, report} = LogRedactor.redact(r, data)
    refute scrubbed.message =~ "123-45-6789"
    refute scrubbed.message =~ "a@b.com"
    refute scrubbed.message =~ "4111-1111-1111"
    assert scrubbed.message =~ "1234"
    assert report.keys_masked == 0
    assert report.credit_cards == 1
    assert report.emails == 1
    assert report.ssns == 1
  end

  test "sensitive-key values are not additionally pattern-scanned", %{r: r} do
    # password's value looks like an SSN, but is redacted wholesale, not counted as an SSN match
    {scrubbed, report} = LogRedactor.redact(r, %{password: "123-45-6789"})
    assert scrubbed.password == "[REDACTED]"
    assert report.keys_masked == 1
    assert report.ssns == 0
  end

  test "empty map yields an all-zero report", %{r: r} do
    assert LogRedactor.redact(r, %{}) ==
             {%{}, %{keys_masked: 0, credit_cards: 0, emails: 0, ssns: 0}}
  end

  # -------------------------------------------------------
  # redact_string/2
  # -------------------------------------------------------

  test "redact_string masks a dashed credit card and reports one card", %{r: r} do
    # TODO
  end

  test "redact_string masks an email keeping the first char", %{r: r} do
    {scrubbed, report} = LogRedactor.redact_string(r, "Contact john.doe@example.com please")
    assert scrubbed =~ "j***@example.com"
    refute scrubbed =~ "john.doe"
    assert report.emails == 1
  end

  test "redact_string masks an SSN", %{r: r} do
    {scrubbed, report} = LogRedactor.redact_string(r, "SSN: 123-45-6789 on file")
    assert scrubbed =~ "***-**-****"
    assert report.ssns == 1
  end

  test "redact_string counts multiple matches of the same type", %{r: r} do
    {scrubbed, report} = LogRedactor.redact_string(r, "123-45-6789 and 987-65-4321")
    assert scrubbed == "***-**-**** and ***-**-****"
    assert report.ssns == 2
  end

  test "redact_string on a clean string returns it unchanged with a zero report", %{r: r} do
    {scrubbed, report} = LogRedactor.redact_string(r, "nothing sensitive here")
    assert scrubbed == "nothing sensitive here"
    assert report == %{keys_masked: 0, credit_cards: 0, emails: 0, ssns: 0}
  end

  # -------------------------------------------------------
  # redact/2 — structs are returned unchanged
  # -------------------------------------------------------

  test "a top-level struct is returned unchanged with an all-zero report", %{r: r} do
    original = %LogRedactorStructFixture{
      name: "erin",
      password: "hunter2",
      note: "ssn 123-45-6789"
    }

    assert LogRedactor.redact(r, original) ==
             {original, %{keys_masked: 0, credit_cards: 0, emails: 0, ssns: 0}}
  end

  test "a struct nested under a non-sensitive key is returned unchanged", %{r: r} do
    profile = %LogRedactorStructFixture{name: "frank", password: "pw", note: "a@b.com"}
    {scrubbed, report} = LogRedactor.redact(r, %{user_id: 7, profile: profile})
    assert scrubbed.user_id == 7
    assert scrubbed.profile == profile
    assert report == %{keys_masked: 0, credit_cards: 0, emails: 0, ssns: 0}
  end

  test "a struct inside a list is returned unchanged", %{r: r} do
    profile = %LogRedactorStructFixture{
      name: "gina",
      password: "pw",
      note: "card 4111111111111234"
    }

    {scrubbed, report} = LogRedactor.redact(r, [profile])
    assert scrubbed == [profile]
    assert report == %{keys_masked: 0, credit_cards: 0, emails: 0, ssns: 0}
  end
end
```
