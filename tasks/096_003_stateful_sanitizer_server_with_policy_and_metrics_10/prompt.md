# Implement the missing function

The specification below is followed by its complete, tested solution —
minus `inc`, whose clause bodies are all `# TODO`. Supply that one
function; the rest of the module is fixed and must stay exactly as shown.

## The task

I need a `Sanitizer` module built as a **GenServer** — I want one server process that cleans user input for us while keeping metrics across all the concurrent callers hitting it. Think of it as the stateful, process-based counterpart to a plain sanitizer: lots of client processes call into the single server, and the server serializes state updates so the counters aggregate safely.

Here's the API I need.

`Sanitizer.start_link(opts \\ [])` starts the server and returns `{:ok, pid}` on success. It should support two options: `:name`, an optional registered name — when it's given, I want to be able to reach the server through every function below by passing that name as `server`; and `:max_filename_length`, an integer defaulting to `255`, where filenames longer than that (after cleaning) get truncated down to that length.

`Sanitizer.sanitize_identifier(server, input)` cleans a SQL identifier. Keep only `[A-Za-z0-9_]`; if it comes out empty after stripping, return `{:error, :empty}`; if it starts with a digit, prepend `_`; otherwise `{:ok, cleaned}`.

`Sanitizer.sanitize_filename(server, input)` cleans a filename. Strip null bytes, strip `/` and `\`, keep only `[A-Za-z0-9_.-]`, collapse runs of 2+ dots down to one dot, and trim leading/trailing dots. If the result is empty → `{:error, :empty}`. Otherwise truncate to `:max_filename_length` if needed and return `{:ok, cleaned}`.

`Sanitizer.strip_html(server, input)` removes HTML. First remove `<script>…</script>` and `<style>…</style>` blocks **including their content** (case-insensitive, matching across newlines), then remove every remaining `<…>` tag while keeping the surrounding text. It returns `{:ok, cleaned, tags_stripped}`, where `tags_stripped` is the total number of `<…>` tag tokens present in the original input.

`Sanitizer.metrics(server)` returns the current metrics map with exactly these integer keys: `:identifiers`, `:identifiers_blocked`, `:filenames`, `:filenames_blocked`, `:filenames_truncated`, `:tags_stripped`, `:html_calls`.

`Sanitizer.reset_metrics(server)` zeros all the metrics and replies `:ok`.

For how the metrics move: every identifier call increments `:identifiers`, and if that call returned `{:error, :empty}` it also increments `:identifiers_blocked`. Every filename call increments `:filenames`; if it returned `{:error, :empty}` it also increments `:filenames_blocked`; and if it was truncated (meaning the cleaned length was strictly greater than `:max_filename_length`) it also increments `:filenames_truncated`. Every `strip_html` call increments `:html_calls` and adds the stripped tag count to `:tags_stripped`.

Since a GenServer serializes calls, I expect the metrics to be exact even when hundreds of processes are calling concurrently. Standard library only, please — no external dependencies.

## The module with `inc` missing

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

  @doc """
  Start the sanitizer server.

  Options:
    * `:name` — optional registered name.
    * `:max_filename_length` — integer, default `255`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
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
    # TODO
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

Output only `inc` (with any `@doc`/`@spec`/`@impl` lines that belong
directly above it) — the single function, not the module.
