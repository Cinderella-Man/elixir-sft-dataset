# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule MaskingServer do
  @moduledoc """
  A `GenServer` that scrubs sensitive data from log-bound maps, keyword lists,
  plain lists, and strings on behalf of concurrent callers.

  The server masks values whose key matches a configured *sensitive key*
  (case-insensitively, for both atom and string keys) and scrubs string values
  using a set of built-in patterns (credit cards, SSNs, and email addresses)
  plus any custom patterns registered at runtime via `add_pattern/3`.

  Because every operation is routed through the `GenServer`, concurrent callers
  are serialized and the cumulative statistics returned by `stats/0` stay exact
  under concurrency.
  """

  use GenServer

  @type server :: GenServer.server()
  @type stats :: %{keys_masked: non_neg_integer(), patterns_applied: non_neg_integer()}

  @masked "[MASKED]"

  @cc_regex ~r/\d(?:[ -]?\d){12,18}/
  @ssn_regex ~r/\d{3}-\d{2}-\d{4}/
  @ssn_replacement "***-**-****"
  @email_regex ~r/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/

  # ── Public API ────────────────────────────────────────────────────────────

  @doc """
  Starts the masking server.

  `opts` is a keyword list. `opts[:sensitive_keys]` is a list of atoms and/or
  strings (defaulting to `[]`); key comparison during masking is
  case-insensitive and works for both atom and string keys.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Masks sensitive data in `data`, returning the same shape.

  Maps and keyword lists are walked recursively; a value under a sensitive key
  becomes `"[MASKED]"`, while other values are walked further. Plain lists are
  walked element-by-element. String values under non-sensitive keys are scrubbed
  with the same patterns as `mask_string/2`. Structs, numbers, atoms, and other
  terms are returned unchanged.
  """
  @spec mask(server(), term()) :: term()
  def mask(server, data) do
    GenServer.call(server, {:mask, data})
  end

  @doc """
  Scans a raw string and masks the built-in patterns plus any registered custom
  patterns, returning the scrubbed string.
  """
  @spec mask_string(server(), String.t()) :: String.t()
  def mask_string(server, string) do
    GenServer.call(server, {:mask_string, string})
  end

  @doc """
  Registers an additional masking pattern applied (in registration order) after
  the built-in patterns for every subsequent string scrubbed.
  """
  @spec add_pattern(server(), Regex.t(), String.t()) :: :ok
  def add_pattern(server, regex, replacement) do
    GenServer.call(server, {:add_pattern, regex, replacement})
  end

  @doc """
  Returns cumulative masking statistics since the server started:
  `%{keys_masked: k, patterns_applied: p}`.
  """
  @spec stats(server()) :: stats()
  def stats(server) do
    GenServer.call(server, :stats)
  end

  # ── GenServer callbacks ───────────────────────────────────────────────────

  @impl true
  def init(opts) do
    sensitive =
      opts
      |> Keyword.get(:sensitive_keys, [])
      |> Enum.map(&normalize_key/1)
      |> MapSet.new()

    state = %{sensitive: sensitive, patterns: [], keys_masked: 0, patterns_applied: 0}
    {:ok, state}
  end

  @impl true
  def handle_call({:mask, data}, _from, state) do
    {result, {ks, pa}} = walk(state, data, {0, 0})

    new_state =
      state
      |> Map.update!(:keys_masked, &(&1 + ks))
      |> Map.update!(:patterns_applied, &(&1 + pa))

    {:reply, result, new_state}
  end

  def handle_call({:mask_string, string}, _from, state) do
    {scrubbed, count} = scrub(state, string)
    new_state = Map.update!(state, :patterns_applied, &(&1 + count))
    {:reply, scrubbed, new_state}
  end

  def handle_call({:add_pattern, regex, replacement}, _from, state) do
    new_state = Map.update!(state, :patterns, &(&1 ++ [{regex, replacement}]))
    {:reply, :ok, new_state}
  end

  def handle_call(:stats, _from, state) do
    stats = %{keys_masked: state.keys_masked, patterns_applied: state.patterns_applied}
    {:reply, stats, state}
  end

  # ── Walking terms ─────────────────────────────────────────────────────────

  # Structs are returned unchanged.
  defp walk(_state, term, acc) when is_struct(term), do: {term, acc}

  defp walk(state, term, acc) when is_map(term) do
    {pairs, acc2} = walk_pairs(state, Map.to_list(term), acc)
    {Map.new(pairs), acc2}
  end

  defp walk(state, term, acc) when is_list(term) do
    if term != [] and Keyword.keyword?(term) do
      walk_pairs(state, term, acc)
    else
      Enum.map_reduce(term, acc, fn element, ac -> walk(state, element, ac) end)
    end
  end

  defp walk(state, term, {ks, pa}) when is_binary(term) do
    {scrubbed, count} = scrub(state, term)
    {scrubbed, {ks, pa + count}}
  end

  defp walk(_state, term, acc), do: {term, acc}

  # Walks a list of `{key, value}` pairs shared by maps and keyword lists.
  defp walk_pairs(state, pairs, acc) do
    Enum.map_reduce(pairs, acc, fn {key, value}, {ks, pa} = ac ->
      if sensitive?(state, key) do
        {{key, @masked}, {ks + 1, pa}}
      else
        {masked_value, ac2} = walk(state, value, ac)
        {{key, masked_value}, ac2}
      end
    end)
  end

  defp sensitive?(state, key) do
    MapSet.member?(state.sensitive, normalize_key(key))
  end

  defp normalize_key(key) when is_atom(key), do: key |> Atom.to_string() |> String.downcase()
  defp normalize_key(key) when is_binary(key), do: String.downcase(key)
  defp normalize_key(key), do: key

  # ── String scrubbing ──────────────────────────────────────────────────────

  # Applies built-in patterns (credit cards, then SSNs, then emails) followed by
  # every registered custom pattern, counting each match replaced.
  defp scrub(state, string) do
    builtins = [
      {@cc_regex, &mask_cc/1},
      {@ssn_regex, @ssn_replacement},
      {@email_regex, &mask_email/1}
    ]

    Enum.reduce(builtins ++ state.patterns, {string, 0}, fn {regex, rep}, {str, count} ->
      matches = length(Regex.scan(regex, str))
      {Regex.replace(regex, str, rep), count + matches}
    end)
  end

  # Masks every digit except the last four, keeping separators intact.
  defp mask_cc(match) do
    chars = String.graphemes(match)
    keep = Enum.count(chars, &digit?/1) - 4

    {masked, _seen} =
      Enum.map_reduce(chars, 0, fn ch, seen ->
        cond do
          digit?(ch) and seen < keep -> {"*", seen + 1}
          digit?(ch) -> {ch, seen + 1}
          true -> {ch, seen}
        end
      end)

    Enum.join(masked)
  end

  # Keeps only the first character of the local part.
  defp mask_email(match) do
    [local, domain] = String.split(match, "@", parts: 2)
    String.first(local) <> "***@" <> domain
  end

  defp digit?(<<c>>) when c in ?0..?9, do: true
  defp digit?(_char), do: false
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule MaskingServerTest do
  use ExUnit.Case, async: false

  setup do
    s = start_supervised!({MaskingServer, [sensitive_keys: [:password, :token, :ssn]]})
    %{s: s}
  end

  # -------------------------------------------------------
  # mask/2 — structural masking
  # -------------------------------------------------------

  test "masks sensitive keys in a flat map", %{s: s} do
    result = MaskingServer.mask(s, %{user: "alice", password: "hunter2"})
    assert result.user == "alice"
    assert result.password == "[MASKED]"
  end

  test "masks sensitive keys regardless of value type", %{s: s} do
    result = MaskingServer.mask(s, %{password: 12345, token: nil})
    assert result.password == "[MASKED]"
    assert result.token == "[MASKED]"
  end

  test "recursively masks nested maps", %{s: s} do
    result = MaskingServer.mask(s, %{user: %{name: "carol", password: "deep"}})
    assert result.user.name == "carol"
    assert result.user.password == "[MASKED]"
  end

  test "masks sensitive keys in a keyword list", %{s: s} do
    result = MaskingServer.mask(s, username: "dave", password: "secret!")
    assert result[:username] == "dave"
    assert result[:password] == "[MASKED]"
  end

  test "leaves non-sensitive keys untouched", %{s: s} do
    result = MaskingServer.mask(s, %{count: 7, role: "admin"})
    assert result.count == 7
    assert result.role == "admin"
  end

  test "pattern-masks string values under non-sensitive keys", %{s: s} do
    # TODO
  end

  # -------------------------------------------------------
  # mask_string/2 — built-in patterns
  # -------------------------------------------------------

  test "masks a dashed credit card", %{s: s} do
    assert MaskingServer.mask_string(s, "4111-1111-1111-1234") == "****-****-****-1234"
  end

  # Single spaces are a documented separator, and separators survive masking.
  test "masks a space-separated credit card keeping the spaces", %{s: s} do
    assert MaskingServer.mask_string(s, "4111 1111 1111 1234") == "**** **** **** 1234"
  end

  # Separators are optional: a bare digit run is still a credit card.
  test "masks an unseparated credit card", %{s: s} do
    assert MaskingServer.mask_string(s, "4111111111111234") == "************1234"
  end

  # The documented length range runs from 13 through 19 digits, and only the
  # final four digits ever survive.
  test "masks cards at the shortest and longest documented lengths", %{s: s} do
    assert MaskingServer.mask_string(s, "4111111111234") == "*********1234"
    assert MaskingServer.mask_string(s, "1234567890123456789") == "***************6789"
  end

  # Irregular grouping is preserved verbatim while every digit but the last
  # four is starred.
  test "masks a 15-digit card with uneven hyphen groups", %{s: s} do
    assert MaskingServer.mask_string(s, "3782-822463-10005") == "****-******-*0005"
  end

  # Card scrubbing applies to string values reached through mask/2 as well.
  test "masks a space-separated card inside a map value", %{s: s} do
    result = MaskingServer.mask(s, %{note: "card 4111 1111 1111 1234 on file"})
    assert result.note == "card **** **** **** 1234 on file"
  end

  test "masks an SSN", %{s: s} do
    result = MaskingServer.mask_string(s, "SSN: 123-45-6789")
    assert result =~ "***-**-****"
    refute result =~ "123-45-6789"
  end

  # -------------------------------------------------------
  # add_pattern/3 — runtime custom patterns
  # -------------------------------------------------------

  test "a registered custom pattern is applied during mask_string", %{s: s} do
    assert MaskingServer.add_pattern(s, ~r/\d{3}-\d{4}/, "[PHONE]") == :ok
    assert MaskingServer.mask_string(s, "call 555-1234 now") == "call [PHONE] now"
  end

  test "custom patterns also apply to string values in mask/2", %{s: s} do
    MaskingServer.add_pattern(s, ~r/\bSECRET\b/, "[X]")
    result = MaskingServer.mask(s, %{note: "the SECRET code"})
    assert result.note == "the [X] code"
  end

  test "built-in patterns still work after a custom pattern is added", %{s: s} do
    MaskingServer.add_pattern(s, ~r/\d{3}-\d{4}/, "[PHONE]")
    assert MaskingServer.mask_string(s, "4111-1111-1111-1234") == "****-****-****-1234"
  end

  # Built-in card masking runs before custom patterns, so a later pattern sees
  # the already-starred card rather than the raw digits.
  test "space-separated cards survive a custom pattern being registered", %{s: s} do
    MaskingServer.add_pattern(s, ~r/\bnow\b/, "[WHEN]")
    assert MaskingServer.mask_string(s, "4111 1111 1111 1234 now") == "**** **** **** 1234 [WHEN]"
  end

  # -------------------------------------------------------
  # stats/1
  # -------------------------------------------------------

  test "stats counts keys_masked across mask calls", %{s: s} do
    MaskingServer.mask(s, %{password: "a", token: "b"})
    MaskingServer.mask(s, %{password: "c"})
    assert MaskingServer.stats(s).keys_masked == 3
  end

  test "stats counts patterns_applied across string scrubs", %{s: s} do
    MaskingServer.mask_string(s, "a@b.com and 123-45-6789")
    assert MaskingServer.stats(s).patterns_applied == 2
  end

  # Each card match counts once toward patterns_applied, whatever its
  # separators or length.
  test "stats counts one pattern per card regardless of separator style", %{s: s} do
    MaskingServer.mask_string(s, "4111 1111 1111 1234")
    MaskingServer.mask_string(s, "4111111111234")
    assert MaskingServer.stats(s).patterns_applied == 2
  end

  test "fresh server reports zero stats", %{s: s} do
    assert MaskingServer.stats(s) == %{keys_masked: 0, patterns_applied: 0}
  end

  # -------------------------------------------------------
  # Concurrency
  # -------------------------------------------------------

  test "keys_masked stays exact under concurrent callers", %{s: s} do
    1..50
    |> Enum.map(fn _ ->
      Task.async(fn -> MaskingServer.mask(s, %{password: "x", note: "hi"}) end)
    end)
    |> Enum.each(&Task.await/1)

    assert MaskingServer.stats(s).keys_masked == 50
  end

  test "server started without :sensitive_keys masks no keys at all" do
    d = start_supervised!({MaskingServer, []}, id: :default_opts_server)
    result = MaskingServer.mask(d, %{password: "hunter2", token: "abc"})
    assert result.password == "hunter2"
    assert result.token == "abc"
    assert MaskingServer.stats(d).keys_masked == 0
  end

  test "sensitive key matching is case-insensitive for string and atom keys", %{s: s} do
    result = MaskingServer.mask(s, %{"PASSWORD" => "x", "Token" => "y", User: "z"})
    assert result["PASSWORD"] == "[MASKED]"
    assert result["Token"] == "[MASKED]"
    assert result[:User] == "z"
    assert MaskingServer.stats(s).keys_masked == 2
  end

  test "plain lists of maps and keyword lists are walked element-by-element", %{s: s} do
    result = MaskingServer.mask(s, [%{password: "a", note: "hi"}, [token: "b", user: "eve"]])
    [first, second] = result
    assert first.password == "[MASKED]"
    assert first.note == "hi"
    assert second[:token] == "[MASKED]"
    assert second[:user] == "eve"
  end

  test "custom patterns are applied in registration order", %{s: s} do
    assert MaskingServer.add_pattern(s, ~r/alpha/, "beta") == :ok
    assert MaskingServer.add_pattern(s, ~r/beta/, "gamma") == :ok
    assert MaskingServer.mask_string(s, "alpha") == "gamma"
  end

  test "structs under non-sensitive keys are returned unchanged", %{s: s} do
    uri = URI.parse("https://example.com/x?mail=john.doe@example.com")
    result = MaskingServer.mask(s, %{when: ~D[2024-01-01], link: uri, n: 7, flag: :on})
    assert result.when == ~D[2024-01-01]
    assert result.link == uri
    assert result.n == 7
    assert result.flag == :on
    assert MaskingServer.stats(s).patterns_applied == 0
  end
end
```
