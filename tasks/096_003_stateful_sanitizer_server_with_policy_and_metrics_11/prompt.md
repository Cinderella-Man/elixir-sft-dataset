# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `start_link` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir module called `Sanitizer` implemented as a **GenServer** that sanitizes user input while tracking metrics across concurrent callers. This is the stateful, process-based counterpart of a plain sanitizer: many client processes call into one server, which serializes state updates and aggregates counters safely.

Public API:

- `Sanitizer.start_link(opts \\ [])` — start the server, returning `{:ok, pid}` on success. Supported options:
  - `:name` — optional registered name. When given, the server can be reached through every function below by passing that name as `server`.
  - `:max_filename_length` — integer, default `255`. Filenames longer than this (after cleaning) are truncated to this length.

- `Sanitizer.sanitize_identifier(server, input)` — clean a SQL identifier. Keep only `[A-Za-z0-9_]`; if empty after stripping return `{:error, :empty}`; if it starts with a digit prepend `_`; otherwise `{:ok, cleaned}`.

- `Sanitizer.sanitize_filename(server, input)` — clean a filename. Strip null bytes, strip `/` and `\`, keep only `[A-Za-z0-9_.-]`, collapse runs of 2+ dots to one dot, trim leading/trailing dots. Empty result → `{:error, :empty}`. Otherwise truncate to `:max_filename_length` if needed and return `{:ok, cleaned}`.

- `Sanitizer.strip_html(server, input)` — remove HTML. First remove `<script>…</script>` and `<style>…</style>` blocks **including their content** (case-insensitive, across newlines), then remove every remaining `<…>` tag, keeping surrounding text. Return `{:ok, cleaned, tags_stripped}` where `tags_stripped` is the total number of `<…>` tag tokens present in the original input.

- `Sanitizer.metrics(server)` — return the current metrics map with exactly these integer keys: `:identifiers`, `:identifiers_blocked`, `:filenames`, `:filenames_blocked`, `:filenames_truncated`, `:tags_stripped`, `:html_calls`.

- `Sanitizer.reset_metrics(server)` — zero all metrics; reply `:ok`.

Metric rules:
- Every identifier call increments `:identifiers`; if it returned `{:error, :empty}` also increment `:identifiers_blocked`.
- Every filename call increments `:filenames`; if it returned `{:error, :empty}` also increment `:filenames_blocked`; if it was truncated (cleaned length strictly greater than `:max_filename_length`) also increment `:filenames_truncated`.
- Every `strip_html` call increments `:html_calls` and adds the stripped tag count to `:tags_stripped`.

Because a GenServer serializes calls, metrics must be exact even when hundreds of processes call concurrently. Standard library only — no external dependencies.

## The module with `start_link` missing

```elixir
defmodule Sanitizer do
  @moduledoc """
  GenServer-based input sanitizer that aggregates metrics across concurrent
  callers. State updates are serialized by the server, so counters remain
  exact even under heavy concurrent load.

  Standard library only — no external dependencies.
  """

  use GenServer

  @typedoc "Aggregated sanitization metrics."
  @type metrics :: %{
          identifiers: non_neg_integer(),
          identifiers_blocked: non_neg_integer(),
          filenames: non_neg_integer(),
          filenames_blocked: non_neg_integer(),
          filenames_truncated: non_neg_integer(),
          tags_stripped: non_neg_integer(),
          html_calls: non_neg_integer()
        }

  @default_metrics %{
    identifiers: 0,
    identifiers_blocked: 0,
    filenames: 0,
    filenames_blocked: 0,
    filenames_truncated: 0,
    tags_stripped: 0,
    html_calls: 0
  }

  # ── Client API ─────────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    # TODO
  end

  @doc """
  Clean a SQL identifier, keeping only `[A-Za-z0-9_]`.

  Returns `{:error, :empty}` when nothing remains, prepends `_` when the
  result starts with a digit, otherwise `{:ok, cleaned}`.
  """
  @spec sanitize_identifier(GenServer.server(), binary()) ::
          {:ok, binary()} | {:error, :empty}
  def sanitize_identifier(server, input) when is_binary(input),
    do: GenServer.call(server, {:identifier, input})

  @doc """
  Clean a filename, stripping path separators and unsafe characters, and
  truncating to `:max_filename_length` when needed.

  Returns `{:error, :empty}` when nothing remains, otherwise `{:ok, cleaned}`.
  """
  @spec sanitize_filename(GenServer.server(), binary()) ::
          {:ok, binary()} | {:error, :empty}
  def sanitize_filename(server, input) when is_binary(input),
    do: GenServer.call(server, {:filename, input})

  @doc """
  Remove HTML from `input`.

  Drops `<script>`/`<style>` blocks including their content, then strips every
  remaining tag. Returns `{:ok, cleaned, tags_stripped}` where `tags_stripped`
  is the number of `<…>` tokens in the original input.
  """
  @spec strip_html(GenServer.server(), binary()) ::
          {:ok, binary(), non_neg_integer()}
  def strip_html(server, input) when is_binary(input),
    do: GenServer.call(server, {:html, input})

  @doc """
  Return the current metrics map.
  """
  @spec metrics(GenServer.server()) :: metrics()
  def metrics(server), do: GenServer.call(server, :metrics)

  @doc """
  Zero all metrics and reply `:ok`.
  """
  @spec reset_metrics(GenServer.server()) :: :ok
  def reset_metrics(server), do: GenServer.call(server, :reset_metrics)

  # ── Server callbacks ───────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    max_len = Keyword.get(opts, :max_filename_length, 255)
    {:ok, %{max_filename_length: max_len, metrics: @default_metrics}}
  end

  @impl true
  def handle_call({:identifier, input}, _from, state) do
    case do_identifier(input) do
      {:ok, s} ->
        {:reply, {:ok, s}, inc(state, [:identifiers])}

      {:error, :empty} = err ->
        {:reply, err, inc(state, [:identifiers, :identifiers_blocked])}
    end
  end

  @impl true
  def handle_call({:filename, input}, _from, %{max_filename_length: max} = state) do
    case do_filename(input) do
      {:error, :empty} = err ->
        {:reply, err, inc(state, [:filenames, :filenames_blocked])}

      {:ok, name} ->
        {truncated?, final} =
          if String.length(name) > max do
            {true, String.slice(name, 0, max)}
          else
            {false, name}
          end

        keys = if truncated?, do: [:filenames, :filenames_truncated], else: [:filenames]
        {:reply, {:ok, final}, inc(state, keys)}
    end
  end

  @impl true
  def handle_call({:html, input}, _from, state) do
    {cleaned, count} = do_strip_html(input)

    metrics =
      state.metrics
      |> Map.update!(:html_calls, &(&1 + 1))
      |> Map.update!(:tags_stripped, &(&1 + count))

    {:reply, {:ok, cleaned, count}, %{state | metrics: metrics}}
  end

  @impl true
  def handle_call(:metrics, _from, state), do: {:reply, state.metrics, state}

  @impl true
  def handle_call(:reset_metrics, _from, state),
    do: {:reply, :ok, %{state | metrics: @default_metrics}}

  # ── Metric helper ──────────────────────────────────────────────────────────

  defp inc(state, keys) do
    metrics = Enum.reduce(keys, state.metrics, fn k, m -> Map.update!(m, k, &(&1 + 1)) end)
    %{state | metrics: metrics}
  end

  # ── Pure sanitization primitives ───────────────────────────────────────────

  defp do_identifier(input) do
    sanitized = String.replace(input, ~r/[^a-zA-Z0-9_]/, "")

    cond do
      sanitized == "" -> {:error, :empty}
      String.match?(sanitized, ~r/\A[0-9]/) -> {:ok, "_" <> sanitized}
      true -> {:ok, sanitized}
    end
  end

  defp do_filename(input) do
    sanitized =
      input
      |> String.replace("\0", "")
      |> String.replace("/", "")
      |> String.replace("\\", "")
      |> String.replace(~r/[^a-zA-Z0-9_\-.]/, "")
      |> String.replace(~r/\.{2,}/, ".")
      |> String.trim(".")

    if sanitized == "", do: {:error, :empty}, else: {:ok, sanitized}
  end

  defp do_strip_html(input) do
    count = length(Regex.scan(~r/<[^>]*>/, input))

    cleaned =
      input
      |> then(fn s -> Regex.replace(~r/<(script|style)\b[^>]*>.*?<\/\1>/is, s, "") end)
      |> then(fn s -> Regex.replace(~r/<[^>]*>/, s, "") end)

    {cleaned, count}
  end
end
```

Give me only the complete implementation of `start_link` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
