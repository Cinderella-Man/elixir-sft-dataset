# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`start_link/1` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `start_link/1`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `start_link/1` missing

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
  are serialized and the cumulative statistics returned by `stats/1` stay exact
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
  # TODO: @spec
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

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
