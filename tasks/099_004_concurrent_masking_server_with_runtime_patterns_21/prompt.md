# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `stats` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir module called `MaskingServer` — a `GenServer` that scrubs sensitive data from log-bound maps, keyword lists, and strings for concurrent callers, supports registering **extra masking patterns at runtime**, and tracks cumulative masking statistics.

I need these functions in the public API:

- `MaskingServer.start_link(opts)` — starts the server. `opts` is a keyword list; `opts[:sensitive_keys]` is a list of atoms and/or strings (defaulting to `[]` when absent). Key comparison during masking must be case-insensitive and work for both atom and string keys. Returns `{:ok, pid}`.

- `MaskingServer.mask(server, data)` — a synchronous call that accepts a map, a keyword list, a plain list, or any other term and returns the same shape with sensitive data scrubbed.
  - Maps and keyword lists are walked recursively. If a key matches a configured sensitive key, its value is replaced with `"[MASKED]"` regardless of the value's type. Non-sensitive keys are preserved and their values continue to be walked.
  - Plain lists (including lists of maps or keyword lists) are walked element-by-element.
  - Every **string value** encountered under a non-sensitive key is passed through the same pattern scrubbing as `mask_string/2`. Values replaced with `"[MASKED]"` because of a sensitive key are **not** additionally pattern-scanned.
  - Structs, numbers, atoms, and other terms are returned unchanged.

- `MaskingServer.mask_string(server, string)` — a synchronous call that scans a raw string and masks the built-in patterns plus any registered custom patterns (see `add_pattern/3`), returning the scrubbed string. The built-in patterns are:
  - **Credit card numbers**: any sequence of 13–19 digits (optionally separated by single spaces or hyphens) — replace every digit except the last 4 with `*`, keeping separators intact. E.g. `"4111-1111-1111-1234"` → `"****-****-****-1234"`.
  - **Email addresses**: keep only the first character of the local part and replace the rest with `***`. E.g. `"john.doe@example.com"` → `"j***@example.com"`.
  - **SSN patterns**: sequences matching `\d{3}-\d{2}-\d{4}` — replace with `"***-**-****"`.

- `MaskingServer.add_pattern(server, regex, replacement)` — registers an additional masking pattern where `regex` is a compiled `Regex` and `replacement` is a string. Returns `:ok`. When scrubbing a string, the built-in patterns are applied first (credit cards, then SSNs, then emails), and then every registered custom pattern is applied in the order it was added, each via a standard regex replace with its replacement string. Registered patterns apply to every subsequent string scrubbed by both `mask_string/2` and `mask/2`.

- `MaskingServer.stats(server)` — returns a map `%{keys_masked: k, patterns_applied: p}` describing cumulative work since the server started:
  - `:keys_masked` — the total number of values replaced with `"[MASKED]"` because their key was sensitive, summed across every `mask/2` call.
  - `:patterns_applied` — the total number of pattern matches replaced (built-in **and** custom patterns) across every string scrubbed by every `mask/2` and `mask_string/2` call.

Because all operations go through the `GenServer`, concurrent callers are serialized and the statistics stay exact under concurrency.

Give me the complete module in a single file. Use only the Elixir standard library and built-in regex support — no external dependencies.

## The module with `stats` missing

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

  def stats(server) do
    # TODO
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

Give me only the complete implementation of `stats` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
