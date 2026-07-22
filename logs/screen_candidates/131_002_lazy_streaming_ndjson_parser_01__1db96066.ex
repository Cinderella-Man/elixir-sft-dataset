defmodule NdjsonStreamer do
  @moduledoc """
  Lazy, line-based parser for very large NDJSON (newline-delimited JSON) files.

  `stream/1` returns a composable `Stream` that reads the file lazily: nothing is
  read from disk until the stream is enumerated, and only as far as the consumer
  actually demands. Memory stays roughly constant regardless of file size, since
  at most a single line (plus its decoded value) is held at any moment.

  Each non-blank line of the file yields exactly one element:

    * `{:ok, value}` — the line decoded as a single JSON value;
    * `{:error, {:invalid_json, raw_line}}` — the line was malformed, where
      `raw_line` is the trimmed line text.

  Blank lines are skipped and produce no element. Malformed lines never abort
  enumeration; they surface inline so the caller can filter, log or count them.

  ## Example

      iex> path = Path.join(System.tmp_dir!(), "ndjson_streamer_doc.ndjson")
      iex> File.write!(path, ~s({"id":1}\\n\\nnope\\n{"id":2}\\n))
      iex> NdjsonStreamer.stream(path) |> Enum.to_list()
      [{:ok, %{"id" => 1}}, {:error, {:invalid_json, "nope"}}, {:ok, %{"id" => 2}}]

  Decoding uses the standard library `JSON` module (Elixir 1.18+), so JSON
  objects become maps with string keys.
  """

  @typedoc "A successfully decoded JSON value, or a malformed-line report."
  @type result :: {:ok, JSON.decode_value()} | {:error, {:invalid_json, String.t()}}

  @doc """
  Returns a lazy `Enumerable` of decoded results for `file_path`.

  The file is read line by line via `File.stream!/2`; nothing is read until the
  returned stream is enumerated, and enumeration stops reading as soon as the
  consumer stops demanding elements. Blank lines are skipped; every other line
  yields `{:ok, value}` or `{:error, {:invalid_json, raw_line}}` in file order.

  Raises `File.Error` only when the underlying file cannot be opened, and only at
  the moment enumeration begins.

  ## Examples

      iex> path = Path.join(System.tmp_dir!(), "ndjson_streamer_take.ndjson")
      iex> File.write!(path, Enum.map_join(1..1000, "\\n", &~s({"id":#{&1}})))
      iex> NdjsonStreamer.stream(path) |> Stream.take(2) |> Enum.to_list()
      [{:ok, %{"id" => 1}}, {:ok, %{"id" => 2}}]

  """
  @spec stream(Path.t()) :: Enumerable.t(result())
  def stream(file_path) do
    file_path
    |> File.stream!([], :line)
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Stream.map(&decode_line/1)
  end

  @doc """
  Decodes a single trimmed NDJSON `line`.

  Returns `{:ok, value}` when `line` holds exactly one complete JSON value, and
  `{:error, {:invalid_json, line}}` otherwise. Never raises on malformed input.
  Trailing content after a complete JSON value (other than whitespace) is treated
  as malformed, since each NDJSON line must stand alone.

  ## Examples

      iex> NdjsonStreamer.decode_line(~s({"id":1,"value":"a"}))
      {:ok, %{"id" => 1, "value" => "a"}}

      iex> NdjsonStreamer.decode_line("[1, 2")
      {:error, {:invalid_json, "[1, 2"}}

  """
  @spec decode_line(String.t()) :: result()
  def decode_line(line) when is_binary(line) do
    case JSON.decode(line) do
      {:ok, value} -> {:ok, value}
      {:error, _reason} -> {:error, {:invalid_json, line}}
    end
  rescue
    _exception -> {:error, {:invalid_json, line}}
  end
end