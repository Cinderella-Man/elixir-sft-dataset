defmodule EvalTask.Bundle do
  @moduledoc """
  Multi-file solution bundles: `<file path="relative/path">…contents…</file>` blocks.

  A multi-file `solution.ex` is not a single Elixir module but a sequence of these
  blocks. This module parses them, materializes them into a temp tree, and validates
  the bundle (rejecting prose fragments, unsafe paths, etc.).
  """

  @block ~r/<file path="([^"]+)">\n(.*?)\n<\/file>/s

  @type file :: {path :: String.t(), contents :: String.t()}

  @doc "True if `source` looks like a `<file>` bundle rather than a plain module."
  @spec bundle?(String.t()) :: boolean()
  def bundle?(source), do: String.contains?(source, "<file path=")

  @doc """
  Drop the `<file path=…>` / `</file>` marker lines, leaving the file contents
  concatenated in bundle order — the convention shipped in the ```` ```elixir ````
  fences of bundle-parent FIM prompts (and what `strip_marker_lines` in the
  embed-resync tool produces).
  """
  @spec strip_markers(String.t()) :: String.t()
  def strip_markers(source) do
    source
    |> String.split("\n")
    |> Enum.reject(&String.match?(String.trim(&1), ~r{^(<file path="[^"]+">|</file>)$}))
    |> Enum.join("\n")
  end

  @doc "Reassemble `{path, contents}` pairs into `<file>` bundle source (parse's inverse)."
  @spec assemble([file()]) :: String.t()
  def assemble(files) do
    Enum.map_join(files, "\n\n", fn {path, body} -> ~s(<file path="#{path}">\n#{body}\n</file>) end)
  end

  @doc "Parse a bundle string into `{path, contents}` pairs (in order)."
  @spec parse(String.t()) :: [file()]
  def parse(source) do
    @block
    |> Regex.scan(source)
    |> Enum.map(fn [_, path, body] -> {path, body} end)
  end

  @doc """
  Validate a parsed bundle. Returns `:ok` or `{:error, reason}`.

  Rejects: empty bundle; duplicate paths; paths escaping the root or absolute;
  files outside `lib|priv|config|test`; and `.ex` source files that contain no
  `defmodule`/`defprotocol`/`defimpl` (prose fragments — the task-017 failure mode).
  """
  @spec validate([file()]) :: :ok | {:error, String.t()}
  def validate([]), do: {:error, "empty bundle: no <file> blocks found"}

  def validate(files) do
    paths = Enum.map(files, &elem(&1, 0))

    cond do
      length(Enum.uniq(paths)) != length(paths) ->
        {:error, "duplicate file paths: #{inspect(paths -- Enum.uniq(paths))}"}

      bad = Enum.find(paths, &unsafe_path?/1) ->
        {:error, "unsafe or out-of-tree path: #{bad}"}

      frag = Enum.find(files, &fragment?/1) ->
        {:error, "fragment (no module definition) in .ex file: #{elem(frag, 0)}"}

      true ->
        :ok
    end
  end

  @doc "Materialize a bundle into `dir`, returning `{source_paths, migration_paths}`."
  @spec materialize([file()], String.t()) :: {[String.t()], [String.t()]}
  def materialize(files, dir) do
    written =
      for {path, body} <- files do
        full = Path.join(dir, path)
        File.mkdir_p!(Path.dirname(full))
        File.write!(full, body)
        {path, full}
      end

    sources = for {path, full} <- written, String.ends_with?(path, ".ex"), do: full

    migrations =
      for {path, full} <- written,
          String.ends_with?(path, ".exs"),
          String.contains?(path, "migrations"),
          do: full

    {sources, migrations}
  end

  @doc "The bundle's `lib/**/*.ex` source contents (for analysis; excludes migrations/config)."
  @spec lib_sources([file()]) :: [String.t()]
  def lib_sources(files) do
    for {path, body} <- files,
        String.ends_with?(path, ".ex"),
        String.starts_with?(path, "lib/"),
        do: body
  end

  @doc "Top-level module names defined by the bundle (for kit-override detection)."
  @spec module_names([file()]) :: [String.t()]
  def module_names(files) do
    for {path, body} <- files,
        String.ends_with?(path, ".ex"),
        [_, name] <- Regex.scan(~r/^\s*defmodule\s+([\w.]+)/m, body),
        do: name
  end

  defp unsafe_path?(path) do
    String.starts_with?(path, "/") or String.contains?(path, "..") or
      not Regex.match?(~r{^(lib|priv|config|test)/}, path)
  end

  defp fragment?({path, body}) do
    String.ends_with?(path, ".ex") and
      not Regex.match?(~r/^\s*(defmodule|defprotocol|defimpl)\s/m, body)
  end
end
