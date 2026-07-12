# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule SanitizerTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} = Sanitizer.start_link()
    {:ok, server: pid}
  end

  describe "identifier sanitization + metrics" do
    test "cleans and counts", %{server: s} do
      assert {:ok, "users"} = Sanitizer.sanitize_identifier(s, "us;ers")
      assert {:ok, "_1t"} = Sanitizer.sanitize_identifier(s, "1t")
      assert {:error, :empty} = Sanitizer.sanitize_identifier(s, "!!!")

      m = Sanitizer.metrics(s)
      assert m.identifiers == 3
      assert m.identifiers_blocked == 1
    end
  end

  describe "filename sanitization + metrics" do
    test "cleans traversal and counts", %{server: s} do
      assert {:ok, "etcpasswd"} = Sanitizer.sanitize_filename(s, "../etc/passwd")
      assert {:error, :empty} = Sanitizer.sanitize_filename(s, "/\\")

      m = Sanitizer.metrics(s)
      assert m.filenames == 2
      assert m.filenames_blocked == 1
      assert m.filenames_truncated == 0
    end

    test "truncates to max_filename_length and counts truncations" do
      {:ok, s} = Sanitizer.start_link(max_filename_length: 5)
      assert {:ok, "abcde"} = Sanitizer.sanitize_filename(s, "abcdefghij")
      assert {:ok, "xy"} = Sanitizer.sanitize_filename(s, "xy")

      m = Sanitizer.metrics(s)
      assert m.filenames == 2
      assert m.filenames_truncated == 1
    end
  end

  describe "html stripping + metrics" do
    test "removes script content and counts tags", %{server: s} do
      # TODO
    end

    test "no tags means zero stripped", %{server: s} do
      assert {:ok, "just text", 0} = Sanitizer.strip_html(s, "just text")
    end
  end

  describe "reset_metrics" do
    test "zeroes everything", %{server: s} do
      Sanitizer.sanitize_identifier(s, "ok")
      Sanitizer.strip_html(s, "<b>x</b>")
      assert :ok = Sanitizer.reset_metrics(s)

      m = Sanitizer.metrics(s)
      assert m.identifiers == 0
      assert m.tags_stripped == 0
      assert m.html_calls == 0
    end
  end

  describe "concurrency" do
    test "metrics stay exact under many concurrent callers", %{server: s} do
      valid =
        for _ <- 1..100 do
          Task.async(fn -> Sanitizer.sanitize_identifier(s, "users") end)
        end

      invalid =
        for _ <- 1..50 do
          Task.async(fn -> Sanitizer.sanitize_identifier(s, "###") end)
        end

      files =
        for _ <- 1..40 do
          Task.async(fn -> Sanitizer.sanitize_filename(s, "../a/b") end)
        end

      Enum.each(valid ++ invalid ++ files, &Task.await/1)

      m = Sanitizer.metrics(s)
      assert m.identifiers == 150
      assert m.identifiers_blocked == 50
      assert m.filenames == 40
      assert m.filenames_blocked == 0
    end
  end
end
```
