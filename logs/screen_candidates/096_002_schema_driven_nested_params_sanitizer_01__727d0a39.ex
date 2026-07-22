defmodule Sanitizer do
  @moduledoc """
  Sanitizes nested parameter maps against a declarative schema.

  `Sanitizer` provides mass-assignment protection plus per-field cleaning for
  controller-style parameter maps with string keys. A schema is a map whose
  values are *field specs* describing how each key should be treated:

    * atom field types — `:text`, `:identifier`, `:filename`, `:integer`,
      `:boolean`;
    * `{:list, inner}` — a list whose elements each match `inner`;
    * a nested schema map — recurse into a nested parameter map.

  Only keys present in the schema survive into the output (whitelist
  semantics). Missing keys are skipped. All field errors are collected and
  keyed by their path (a list of string keys and integer list indices).
  """

  @type reason ::
          :not_a_string
          | :empty
          | :not_an_integer
          | :not_a_boolean
          | :expected_map
          | :expected_list

  @type path :: [String.t() | non_neg_integer()]
  @type field_spec :: atom() | {:list, field_spec()} | map()

  @doc """
  Sanitizes `params` against `schema`.

  Returns `{:ok, cleaned}` when every present field validates, otherwise
  `{:error, errors}` where `errors` maps each failing path to a reason atom.

  ## Examples

      iex> Sanitizer.sanitize(%{"name" => " Bob "}, %{"name" => :text})
      {:ok, %{"name" => "Bob"}}

      iex> Sanitizer.sanitize(%{"profile" => "nope"},
      ...>   %{"profile" => %{"bio" => :text}})
      {:error, %{["profile"] => :expected_map}}

  """
  @spec sanitize(map(), map()) :: {:ok, map()} | {:error, %{path() => reason()}}
  def sanitize(params, schema) when is_map(params) and is_map(schema) do
    {cleaned, errors} = sanitize_map(params, schema, [])

    if errors == %{} do
      {:ok, cleaned}
    else
      {:error, errors}
    end
  end

  @doc """
  Cleans a string into a safe SQL identifier.

  Keeps only `[A-Za-z0-9_]`, prepends `_` when the result starts with a digit,
  and returns `{:error, :empty}` when nothing remains.

  ## Examples

      iex> Sanitizer.sql_identifier("1st col!")
      {:ok, "_1stcol"}

      iex> Sanitizer.sql_identifier("***")
      {:error, :empty}

  """
  @spec sql_identifier(binary()) :: {:ok, binary()} | {:error, :empty}
  def sql_identifier(value) when is_binary(value) do
    cleaned = String.replace(value, ~r/[^A-Za-z0-9_]/, "")

    cond do
      cleaned == "" -> {:error, :empty}
      String.match?(cleaned, ~r/^[0-9]/) -> {:ok, "_" <> cleaned}
      true -> {:ok, cleaned}
    end
  end

  @doc """
  Cleans a string into a safe filename.

  Strips null bytes, `/`, and `\\`, keeps only `[A-Za-z0-9_.-]`, collapses runs
  of two or more dots to a single dot, and trims leading/trailing dots.
  Returns `{:error, :empty}` when nothing remains.

  ## Examples

      iex> Sanitizer.filename("../etc/passwd")
      {:ok, "etcpasswd"}

      iex> Sanitizer.filename("...")
      {:error, :empty}

  """
  @spec filename(binary()) :: {:ok, binary()} | {:error, :empty}
  def filename(value) when is_binary(value) do
    cleaned =
      value
      |> String.replace("\0", "")
      |> String.replace(["/", "\\"], "")
      |> String.replace(~r/[^A-Za-z0-9_.-]/, "")
      |> String.replace(~r/\.{2,}/, ".")
      |> String.trim(".")

    if cleaned == "" do
      {:error, :empty}
    else
      {:ok, cleaned}
    end
  end

  # --- internal walking ----------------------------------------------------

  @spec sanitize_map(map(), map(), path()) :: {map(), %{path() => reason()}}
  defp sanitize_map(params, schema, path) do
    Enum.reduce(schema, {%{}, %{}}, fn {key, spec}, {acc, errs} ->
      case Map.fetch(params, key) do
        :error ->
          {acc, errs}

        {:ok, value} ->
          case apply_spec(value, spec, path ++ [key]) do
            {:ok, cleaned} -> {Map.put(acc, key, cleaned), errs}
            {:error, field_errs} -> {acc, Map.merge(errs, field_errs)}
          end
      end
    end)
  end

  @spec apply_spec(term(), field_spec(), path()) ::
          {:ok, term()} | {:error, %{path() => reason()}}
  defp apply_spec(value, :text, _path) when is_binary(value) do
    {:ok, clean_text(value)}
  end

  defp apply_spec(_value, :text, path) do
    {:error, %{path => :not_a_string}}
  end

  defp apply_spec(value, :identifier, path) when is_binary(value) do
    case sql_identifier(value) do
      {:ok, cleaned} -> {:ok, cleaned}
      {:error, reason} -> {:error, %{path => reason}}
    end
  end

  defp apply_spec(_value, :identifier, path) do
    {:error, %{path => :not_a_string}}
  end

  defp apply_spec(value, :filename, path) when is_binary(value) do
    case filename(value) do
      {:ok, cleaned} -> {:ok, cleaned}
      {:error, reason} -> {:error, %{path => reason}}
    end
  end

  defp apply_spec(_value, :filename, path) do
    {:error, %{path => :not_a_string}}
  end

  defp apply_spec(value, :integer, _path) when is_integer(value) do
    {:ok, value}
  end

  defp apply_spec(value, :integer, path) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> {:ok, int}
      _ -> {:error, %{path => :not_an_integer}}
    end
  end

  defp apply_spec(_value, :integer, path) do
    {:error, %{path => :not_an_integer}}
  end

  defp apply_spec(value, :boolean, _path) when is_boolean(value) do
    {:ok, value}
  end

  defp apply_spec("true", :boolean, _path), do: {:ok, true}
  defp apply_spec("false", :boolean, _path), do: {:ok, false}

  defp apply_spec(_value, :boolean, path) do
    {:error, %{path => :not_a_boolean}}
  end

  defp apply_spec(value, {:list, inner}, path) when is_list(value) do
    {cleaned_rev, errs} =
      value
      |> Enum.with_index()
      |> Enum.reduce({[], %{}}, fn {elem, idx}, {acc, e} ->
        case apply_spec(elem, inner, path ++ [idx]) do
          {:ok, cleaned} -> {[cleaned | acc], e}
          {:error, field_errs} -> {acc, Map.merge(e, field_errs)}
        end
      end)

    if errs == %{} do
      {:ok, Enum.reverse(cleaned_rev)}
    else
      {:error, errs}
    end
  end

  defp apply_spec(_value, {:list, _inner}, path) do
    {:error, %{path => :expected_list}}
  end

  defp apply_spec(value, spec, path) when is_map(spec) and is_map(value) do
    {cleaned, errs} = sanitize_map(value, spec, path)

    if errs == %{} do
      {:ok, cleaned}
    else
      {:error, errs}
    end
  end

  defp apply_spec(_value, spec, path) when is_map(spec) do
    {:error, %{path => :expected_map}}
  end

  # --- field cleaning helpers ----------------------------------------------

  @spec clean_text(binary()) :: binary()
  defp clean_text(value) do
    value
    |> strip_c0()
    |> String.trim()
    |> escape_html()
  end

  @spec strip_c0(binary()) :: binary()
  defp strip_c0(str) do
    str
    |> String.to_charlist()
    |> Enum.filter(fn c -> c >= 0x20 or c in [?\t, ?\n, ?\r] end)
    |> List.to_string()
  end

  @spec escape_html(binary()) :: binary()
  defp escape_html(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end
end