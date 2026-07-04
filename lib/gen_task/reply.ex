defmodule GenTask.Reply do
  @moduledoc """
  Parse and validate a `claude -p` reply.

  Model replies use the repo's own `<file path="...">…</file>` bundle convention
  (parsed by `EvalTask.Bundle.parse/1`). Each body is then run through
  `sanitize_file_body/1` to strip a wrapping markdown code fence — models add
  fences even when told not to, and a stray ```` ``` ```` line would be written
  into the `.ex`/`.exs` file and break compilation.

  Per-step contract validators enforce the shape each generation step must return
  (see `docs/04-task-generation-loop.md` §7).
  """

  @fence_open ~r/^\s*```[a-zA-Z0-9_+.\-]*\s*$/
  @fence_close ~r/^\s*```\s*$/

  @doc """
  Parse reply `text` into a `%{path => sanitized_body}` map (last write wins on
  duplicate paths — `EvalTask.Bundle.parse/1` preserves order).
  """
  @spec parse(String.t()) :: %{String.t() => String.t()}
  def parse(text) do
    text
    |> EvalTask.Bundle.parse()
    |> Enum.map(fn {path, body} -> {path, sanitize_file_body(body)} end)
    |> Map.new()
  end

  @doc """
  Strip a single wrapping markdown code fence from `body`.

  Removes a leading fence line (```` ``` ```` optionally followed by a language
  word) and its matching trailing fence line. A no-op when the body is not
  fence-wrapped.
  """
  @spec sanitize_file_body(String.t()) :: String.t()
  def sanitize_file_body(body) do
    lines = String.split(body, "\n")

    with [first | rest] when rest != [] <- lines,
         true <- Regex.match?(@fence_open, first),
         close_idx when is_integer(close_idx) <- closing_fence_index(rest) do
      rest |> Enum.take(close_idx) |> Enum.join("\n")
    else
      _ -> body
    end
  end

  # Index in `rest` of the closing fence, allowing trailing blank/whitespace-only
  # lines after it (the bundle parser keeps a trailing newline when the model puts a
  # blank line before `</file>`). Returns `nil` if the last non-blank line is not a
  # fence close.
  defp closing_fence_index(rest) do
    rest
    |> Enum.with_index()
    |> Enum.reverse()
    |> Enum.find(fn {line, _i} -> String.trim(line) != "" end)
    |> case do
      {line, idx} -> if Regex.match?(@fence_close, line), do: idx, else: nil
      nil -> nil
    end
  end

  # ---------------------------------------------------------------------------
  # Per-step contract validation
  # ---------------------------------------------------------------------------

  @type files :: %{String.t() => String.t()}

  @doc "Validate a base-task reply: `prompt.md` + a `…Test` ExUnit harness."
  @spec validate_task(files()) :: :ok | {:error, String.t()}
  def validate_task(files) do
    with :ok <- require_nonempty(files, "prompt.md"),
         :ok <- require_nonempty(files, "test_harness.exs"),
         :ok <- require_test_harness(files["test_harness.exs"]) do
      :ok
    end
  end

  @doc "Validate an answer reply: a non-empty `solution.ex` containing `defmodule`."
  @spec validate_answer(files()) :: :ok | {:error, String.t()}
  def validate_answer(files) do
    with :ok <- require_nonempty(files, "solution.ex"),
         :ok <- require_defmodule(files["solution.ex"], "solution.ex") do
      :ok
    end
  end

  @doc """
  Validate a fix reply: a non-empty subset of `{solution.ex, test_harness.exs}`
  and **no** `prompt.md` (the task statement must not drift).
  """
  @spec validate_fix(files()) :: :ok | {:error, String.t()}
  def validate_fix(files) do
    cond do
      Map.has_key?(files, "prompt.md") ->
        {:error, "a fix must not return prompt.md (the task statement is immutable)"}

      not (has_body?(files, "solution.ex") or has_body?(files, "test_harness.exs")) ->
        {:error, "a fix must return at least one of solution.ex / test_harness.exs"}

      Map.has_key?(files, "test_harness.exs") ->
        require_test_harness(files["test_harness.exs"])

      true ->
        :ok
    end
  end

  @doc """
  Validate a variations reply: for each of `v1`..`vN` (default 3), a path-prefixed
  triplet (`vN/prompt.md`, `vN/test_harness.exs`, `vN/solution.ex`) plus an idea
  entry (`vN/idea.md`).
  """
  @spec validate_variations(files(), pos_integer()) :: :ok | {:error, String.t()}
  def validate_variations(files, count \\ 3) do
    Enum.reduce_while(1..count, :ok, fn n, _acc ->
      prefix = "v#{n}/"

      case validate_variation_dir(files, prefix) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  @doc """
  Per-slot variation validation for salvage: returns `{valid_ns, errors}` where
  `valid_ns` are the reply indices (1..count) whose `vN/` group passes the full
  contract, and `errors` describe the rest. One malformed group used to discard the
  whole (large, expensive) reply — the valid groups are worth keeping.
  """
  @spec valid_variation_slots(files(), pos_integer()) :: {[pos_integer()], [String.t()]}
  def valid_variation_slots(files, count \\ 3) do
    {valid, errors} =
      Enum.reduce(1..count, {[], []}, fn n, {ok, errs} ->
        case validate_variation_dir(files, "v#{n}/") do
          :ok -> {[n | ok], errs}
          {:error, msg} -> {ok, ["v#{n}: #{msg}" | errs]}
        end
      end)

    {Enum.reverse(valid), Enum.reverse(errors)}
  end

  defp validate_variation_dir(files, prefix) do
    with :ok <- require_nonempty(files, prefix <> "prompt.md"),
         :ok <- require_nonempty(files, prefix <> "test_harness.exs"),
         :ok <- require_nonempty(files, prefix <> "solution.ex"),
         :ok <- require_nonempty(files, prefix <> "idea.md"),
         :ok <- require_test_harness(files[prefix <> "test_harness.exs"]),
         :ok <- require_defmodule(files[prefix <> "solution.ex"], prefix <> "solution.ex") do
      :ok
    end
  end

  @doc """
  Validate a FIM per-candidate reply: `prompt.md` carrying a fenced `elixir`
  skeleton with a `# TODO` marker, plus a non-empty `solution.ex`.
  """
  @spec validate_fim(files()) :: :ok | {:error, String.t()}
  def validate_fim(files) do
    with :ok <- require_nonempty(files, "prompt.md"),
         :ok <- require_nonempty(files, "solution.ex"),
         :ok <- require_fim_skeleton(files["prompt.md"]) do
      :ok
    end
  end

  # ---------------------------------------------------------------------------
  # shared checks
  # ---------------------------------------------------------------------------

  defp has_body?(files, path) do
    case Map.get(files, path) do
      nil -> false
      body -> String.trim(body) != ""
    end
  end

  defp require_nonempty(files, path) do
    if has_body?(files, path), do: :ok, else: {:error, "missing or empty file: #{path}"}
  end

  defp require_defmodule(body, path) do
    if Regex.match?(~r/\bdefmodule\s/, body),
      do: :ok,
      else: {:error, "#{path} contains no defmodule"}
  end

  defp require_test_harness(body) do
    cond do
      not Regex.match?(~r/defmodule\s+[\w.]*Test\b/, body) ->
        {:error, "test_harness.exs must define a `defmodule …Test` module"}

      not Regex.match?(~r/use\s+ExUnit\.Case/, body) ->
        {:error, "test_harness.exs must `use ExUnit.Case`"}

      true ->
        :ok
    end
  end

  defp require_fim_skeleton(prompt_md) do
    cond do
      not Regex.match?(~r/```elixir\n.*?\n```/s, prompt_md) ->
        {:error, "FIM prompt.md must contain a fenced ```elixir skeleton"}

      not Regex.match?(~r/#\s*TODO/i, prompt_md) ->
        {:error, "FIM prompt.md skeleton must contain a `# TODO` marker"}

      true ->
        :ok
    end
  end
end
