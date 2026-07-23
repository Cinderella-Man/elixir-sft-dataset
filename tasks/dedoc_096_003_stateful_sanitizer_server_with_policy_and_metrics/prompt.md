# Restore the documentation

The module below works and is fully tested — its behavior is final. What it
lost is every piece of documentation. Put it back:

- a `@moduledoc` covering purpose and usage,
- a `@doc` on each public function,
- a `@spec` on each public function (plus `@type`s where they clarify).

And keep your hands off the code itself: no renames, no refactors, no added
or removed functions, identical behavior everywhere. Return the whole
documented module in one file.

## The module

```elixir
defmodule Sanitizer do
  use GenServer

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
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  def sanitize_identifier(server, input) when is_binary(input),
    do: GenServer.call(server, {:identifier, input})

  def sanitize_filename(server, input) when is_binary(input),
    do: GenServer.call(server, {:filename, input})

  def strip_html(server, input) when is_binary(input),
    do: GenServer.call(server, {:html, input})

  def metrics(server), do: GenServer.call(server, :metrics)

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
