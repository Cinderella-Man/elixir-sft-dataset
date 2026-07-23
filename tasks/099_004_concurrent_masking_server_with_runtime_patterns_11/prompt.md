# Implement the missing function

Below you'll find a task's full specification, then a working, tested
solution with one gap: `handle_call` — every clause body swapped for
`# TODO`. Rebuild exactly that function so the module passes the task's
whole suite again, and leave every other line precisely as shown.

## The task

I'm about to wire log scrubbing into our pipeline and I need a module from you first — call it `MaskingServer`. It should be a `GenServer` that scrubs sensitive data out of log-bound maps, keyword lists, and strings on behalf of concurrent callers, lets me register **extra masking patterns at runtime**, and keeps a running tally of cumulative masking statistics.

Here's the public API I'm going to call against.

`MaskingServer.start_link(opts)` starts the server. `opts` is a keyword list, and `opts[:sensitive_keys]` is a list of atoms and/or strings, defaulting to `[]` when it isn't there. When masking, key comparison has to be case-insensitive, and it has to work for both atom keys and string keys. It returns `{:ok, pid}`.

`MaskingServer.mask(server, data)` is a synchronous call. I'll hand it a map, a keyword list, a plain list, or any other term, and I expect the same shape back with the sensitive data scrubbed. Maps and keyword lists get walked recursively: if a key matches one of the configured sensitive keys, its value is replaced with `"[MASKED]"` no matter what type that value is; non-sensitive keys are preserved and their values keep getting walked. Plain lists — including lists of maps or lists of keyword lists — get walked element by element. Every **string value** you hit under a non-sensitive key goes through exactly the same pattern scrubbing as `mask_string/2`. Values that were replaced with `"[MASKED]"` because of a sensitive key must **not** be pattern-scanned on top of that. Structs, numbers, atoms, and anything else come back unchanged.

`MaskingServer.mask_string(server, string)` is also a synchronous call: it scans a raw string, masks the built-in patterns plus whatever custom patterns have been registered (see `add_pattern/3`), and returns the scrubbed string. The built-in ones I need are credit card numbers — any sequence of 13–19 digits, optionally separated by single spaces or hyphens, where every digit except the last 4 becomes `*` and the separators stay intact, so `"4111-1111-1111-1234"` comes back as `"****-****-****-1234"`; email addresses — keep only the first character of the local part and replace the rest with `***`, so `"john.doe@example.com"` becomes `"j***@example.com"`; and SSN patterns — anything matching `\d{3}-\d{2}-\d{4}` gets replaced with `"***-**-****"`.

`MaskingServer.add_pattern(server, regex, replacement)` registers an additional masking pattern, where `regex` is a compiled `Regex` and `replacement` is a string. It returns `:ok`. Ordering matters to me: when a string is scrubbed, the built-in patterns run first (credit cards, then SSNs, then emails), and after that every registered custom pattern is applied in the order it was added, each one via a standard regex replace with its replacement string. Registered patterns apply to every string scrubbed from then on, by both `mask_string/2` and `mask/2`.

`MaskingServer.stats(server)` returns a map `%{keys_masked: k, patterns_applied: p}` covering cumulative work since the server started. `:keys_masked` is the total number of values replaced with `"[MASKED]"` because their key was sensitive, summed across every `mask/2` call. `:patterns_applied` is the total number of pattern matches replaced — built-in **and** custom patterns — across every string scrubbed by every `mask/2` and `mask_string/2` call.

Since every operation goes through the `GenServer`, concurrent callers end up serialized and the statistics stay exact under concurrency, which is the property I care about most here.

Send me the complete module in a single file, please. Elixir standard library and built-in regex support only — no external dependencies.

## The module with `handle_call` missing

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

  def handle_call({:mask, data}, _from, state) do
    # TODO
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

Reply with `handle_call` alone (bring along any `@doc`/`@spec`/`@impl` lines
that belong directly above it) — just the function, never the whole
module.
