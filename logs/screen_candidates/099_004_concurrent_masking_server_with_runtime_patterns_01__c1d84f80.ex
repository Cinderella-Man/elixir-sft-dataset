defmodule MaskingServer do
  @moduledoc """
  A `GenServer` that scrubs sensitive data from log-bound maps, keyword lists,
  and strings on behalf of concurrent callers.

  The server understands three kinds of masking work:

    * **Sensitive keys** — values stored under a configured key (case-insensitive,
      atom or string) are replaced wholesale with `"[MASKED]"`.
    * **Built-in patterns** — credit-card numbers, U.S. Social Security numbers, and
      email addresses are scrubbed inside every string value it encounters.
    * **Custom patterns** — additional `Regex`/replacement pairs registered at
      runtime via `add_pattern/3`.

  Every operation is a synchronous `GenServer` call, so concurrent callers are
  serialized and the cumulative statistics returned by `stats/0` stay exact.
  """

  use GenServer

  @card_regex ~r/(?<!\d)\d(?:[ \-]?\d){12,18}(?!\d)/
  @ssn_regex ~r/\d{3}-\d{2}-\d{4}/
  @email_regex ~r/([A-Za-z0-9._%+\-]+)@([A-Za-z0-9.\-]+\.[A-Za-z]{2,})/

  # ── Public API ──────────────────────────────────────────────────────────────

  @doc """
  Starts the masking server.

  `opts` is a keyword list. `opts[:sensitive_keys]` is a list of atoms and/or
  strings (defaulting to `[]`); those keys are matched case-insensitively during
  masking, for both atom and string keys.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, [])
  end

  @doc """
  Scrubs `data` and returns the same shape with sensitive information removed.

  Maps and keyword lists are walked recursively: a value under a sensitive key
  becomes `"[MASKED]"`, while other values keep being walked. Plain lists are
  walked element-by-element. Every string value under a non-sensitive key is
  pattern-scrubbed just like `mask_string/2`. Structs, numbers, atoms, and other
  terms are returned unchanged.
  """
  @spec mask(GenServer.server(), term()) :: term()
  def mask(server, data) do
    GenServer.call(server, {:mask, data})
  end

  @doc """
  Scrubs a raw `string`, masking the built-in patterns (credit cards, SSNs, and
  emails) plus any patterns registered with `add_pattern/3`, and returns the
  scrubbed string.
  """
  @spec mask_string(GenServer.server(), String.t()) :: String.t()
  def mask_string(server, string) do
    GenServer.call(server, {:mask_string, string})
  end

  @doc """
  Registers an additional masking pattern.

  `regex` is a compiled `Regex` and `replacement` is a string. Built-in patterns
  are always applied first (credit cards, then SSNs, then emails); custom
  patterns are then applied in registration order via a standard regex replace.
  Applies to every subsequent string scrubbed by `mask_string/2` and `mask/2`.
  """
  @spec add_pattern(GenServer.server(), Regex.t(), String.t()) :: :ok
  def add_pattern(server, regex, replacement) do
    GenServer.call(server, {:add_pattern, regex, replacement})
  end

  @doc """
  Returns cumulative masking statistics since the server started.

  `:keys_masked` is the total number of values replaced with `"[MASKED]"` because
  their key was sensitive. `:patterns_applied` is the total number of pattern
  matches replaced (built-in and custom) across every scrubbed string.
  """
  @spec stats(GenServer.server()) ::
          %{keys_masked: non_neg_integer(), patterns_applied: non_neg_integer()}
  def stats(server) do
    GenServer.call(server, :stats)
  end

  # ── GenServer callbacks ─────────────────────────────────────────────────────

  @impl GenServer
  def init(opts) do
    keys =
      opts
      |> Keyword.get(:sensitive_keys, [])
      |> Enum.map(&normalize_key/1)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    state = %{keys: keys, patterns: [], keys_masked: 0, patterns_applied: 0}
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:mask, data}, _from, state) do
    context = %{keys: state.keys, patterns: state.patterns}
    {result, kc, pc} = walk(data, context)

    new_state = %{
      state
      | keys_masked: state.keys_masked + kc,
        patterns_applied: state.patterns_applied + pc
    }

    {:reply, result, new_state}
  end

  def handle_call({:mask_string, string}, _from, state) do
    {scrubbed, count} = scrub(string, state.patterns)
    new_state = %{state | patterns_applied: state.patterns_applied + count}
    {:reply, scrubbed, new_state}
  end

  def handle_call({:add_pattern, regex, replacement}, _from, state) do
    new_patterns = state.patterns ++ [{regex, replacement}]
    {:reply, :ok, %{state | patterns: new_patterns}}
  end

  def handle_call(:stats, _from, state) do
    reply = %{keys_masked: state.keys_masked, patterns_applied: state.patterns_applied}
    {:reply, reply, state}
  end

  # ── Recursive walking ───────────────────────────────────────────────────────

  # Returns `{scrubbed_value, keys_masked_count, patterns_applied_count}`.
  defp walk(data, _ctx) when is_struct(data), do: {data, 0, 0}

  defp walk(data, ctx) when is_map(data), do: walk_map(data, ctx)

  defp walk(data, ctx) when is_list(data) do
    if data != [] and Keyword.keyword?(data) do
      walk_keyword(data, ctx)
    else
      walk_list(data, ctx)
    end
  end

  defp walk(data, ctx) when is_binary(data) do
    {scrubbed, count} = scrub(data, ctx.patterns)
    {scrubbed, 0, count}
  end

  defp walk(data, _ctx), do: {data, 0, 0}

  defp walk_map(map, ctx) do
    Enum.reduce(map, {%{}, 0, 0}, fn {key, value}, {acc, kc, pc} ->
      if sensitive?(key, ctx.keys) do
        {Map.put(acc, key, "[MASKED]"), kc + 1, pc}
      else
        {value2, kc2, pc2} = walk(value, ctx)
        {Map.put(acc, key, value2), kc + kc2, pc + pc2}
      end
    end)
  end

  defp walk_keyword(list, ctx) do
    {acc, kc, pc} =
      Enum.reduce(list, {[], 0, 0}, fn {key, value}, {acc, kc, pc} ->
        if sensitive?(key, ctx.keys) do
          {[{key, "[MASKED]"} | acc], kc + 1, pc}
        else
          {value2, kc2, pc2} = walk(value, ctx)
          {[{key, value2} | acc], kc + kc2, pc + pc2}
        end
      end)

    {Enum.reverse(acc), kc, pc}
  end

  defp walk_list(list, ctx) do
    {acc, kc, pc} =
      Enum.reduce(list, {[], 0, 0}, fn element, {acc, kc, pc} ->
        {element2, kc2, pc2} = walk(element, ctx)
        {[element2 | acc], kc + kc2, pc + pc2}
      end)

    {Enum.reverse(acc), kc, pc}
  end

  # ── Key handling ────────────────────────────────────────────────────────────

  defp sensitive?(key, keys) do
    case normalize_key(key) do
      nil -> false
      norm -> MapSet.member?(keys, norm)
    end
  end

  defp normalize_key(key) when is_atom(key), do: key |> Atom.to_string() |> String.downcase()
  defp normalize_key(key) when is_binary(key), do: String.downcase(key)
  defp normalize_key(_key), do: nil

  # ── String scrubbing ────────────────────────────────────────────────────────

  # Returns `{scrubbed_string, total_matches_replaced}`.
  defp scrub(string, patterns) do
    {s1, c1} = mask_cards(string)
    {s2, c2} = mask_ssns(s1)
    {s3, c3} = mask_emails(s2)
    {s4, c4} = apply_custom(s3, patterns)
    {s4, c1 + c2 + c3 + c4}
  end

  defp mask_cards(string) do
    count = length(Regex.scan(@card_regex, string))
    new = Regex.replace(@card_regex, string, fn match -> mask_card_digits(match) end)
    {new, count}
  end

  defp mask_card_digits(match) do
    chars = String.to_charlist(match)
    total = Enum.count(chars, &(&1 in ?0..?9))

    {masked, _idx} =
      Enum.map_reduce(chars, 0, fn ch, idx ->
        cond do
          ch in ?0..?9 and idx < total - 4 -> {?*, idx + 1}
          ch in ?0..?9 -> {ch, idx + 1}
          true -> {ch, idx}
        end
      end)

    List.to_string(masked)
  end

  defp mask_ssns(string) do
    count = length(Regex.scan(@ssn_regex, string))
    {Regex.replace(@ssn_regex, string, "***-**-****"), count}
  end

  defp mask_emails(string) do
    count = length(Regex.scan(@email_regex, string))

    new =
      Regex.replace(@email_regex, string, fn _match, local, domain ->
        "#{String.first(local)}***@#{domain}"
      end)

    {new, count}
  end

  defp apply_custom(string, patterns) do
    Enum.reduce(patterns, {string, 0}, fn {regex, replacement}, {current, count} ->
      matches = length(Regex.scan(regex, current))
      {Regex.replace(regex, current, replacement), count + matches}
    end)
  end
end