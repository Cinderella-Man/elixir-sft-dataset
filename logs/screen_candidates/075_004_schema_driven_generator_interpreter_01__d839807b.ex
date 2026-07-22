defmodule SchemaGenerators do
  @moduledoc """
  Turn a declarative schema description into a `StreamData` generator at runtime.

  Rather than hand-writing a bespoke generator for every data shape used in a property
  test, `SchemaGenerators.from_schema/1` interprets a plain-data schema term and returns
  a `%StreamData{}` generator whose produced values always conform to that schema.

  ## Schema grammar

    * `:integer` — any integer.
    * `{:integer, min, max}` — an integer in `min..max` (requires `min <= max`).
    * `:boolean` — a boolean.
    * `:string` — an alphanumeric string (possibly empty).
    * `{:string, min_len, max_len}` — an alphanumeric string of length in `min_len..max_len`.
    * `{:enum, values}` — one of the given non-empty list of literal `values`.
    * `{:list, schema}` — a list of 0 or more values conforming to `schema`.
    * `{:list, schema, opts}` — a list whose length is in
      `Keyword.get(opts, :min, 0)..Keyword.get(opts, :max, 10)`.
    * `{:map, schema_map}` — a fixed-shape map with exactly the keys of `schema_map`.
    * `{:optional, schema}` — either `nil` or a value conforming to `schema`.
    * `{:one_of, schemas}` — a value conforming to one of the given non-empty `schemas`.

  Every constraint is enforced by the generator itself, so consumers never need to filter
  generated data. Because the result is an ordinary `%StreamData{}` struct, it composes with
  all the usual `StreamData` combinators and shrinks as you would expect.

  ## Examples

      use ExUnitProperties

      schema =
        {:map,
         %{
           id: {:integer, 1, 1_000},
           name: {:string, 1, 20},
           role: {:enum, [:admin, :user]},
           tags: {:list, :string, min: 1, max: 3},
           nickname: {:optional, :string}
         }}

      property "users conform to the schema" do
        check all user <- SchemaGenerators.from_schema(schema) do
          assert user.id in 1..1_000
          assert user.role in [:admin, :user]
        end
      end

  """

  @typedoc "A declarative schema term understood by `from_schema/1`."
  @type schema ::
          :integer
          | {:integer, integer(), integer()}
          | :boolean
          | :string
          | {:string, non_neg_integer(), non_neg_integer()}
          | {:enum, [term(), ...]}
          | {:list, schema()}
          | {:list, schema(), keyword()}
          | {:map, %{optional(term()) => schema()}}
          | {:optional, schema()}
          | {:one_of, [schema(), ...]}

  @default_min_length 0
  @default_max_length 10

  @doc """
  Build a `StreamData` generator for the given `schema`.

  The schema is walked recursively, so nested schemas (a list of maps, a map holding an
  optional list, and so on) yield correspondingly nested generators. All constraints are
  baked into the generator; the returned values never need to be filtered.

  Raises `ArgumentError` if the schema term is not part of the supported grammar or if its
  arguments are invalid (for example an empty `:enum` list, or an integer range whose `min`
  is greater than its `max`).

  ## Examples

      iex> gen = SchemaGenerators.from_schema({:integer, 1, 5})
      iex> match?(%StreamData{}, gen)
      true

      iex> gen = SchemaGenerators.from_schema({:enum, [:a, :b]})
      iex> Enum.all?(Enum.take(StreamData.resize(gen, 10), 20), &(&1 in [:a, :b]))
      true

  """
  @spec from_schema(schema()) :: StreamData.t(term())
  def from_schema(:integer), do: StreamData.integer()

  def from_schema({:integer, min, max}) when is_integer(min) and is_integer(max) do
    unless min <= max do
      raise ArgumentError,
            "invalid {:integer, min, max} schema: expected min <= max, got: #{min} > #{max}"
    end

    StreamData.integer(min..max)
  end

  def from_schema(:boolean), do: StreamData.boolean()

  def from_schema(:string), do: StreamData.string(:alphanumeric)

  def from_schema({:string, min_len, max_len})
      when is_integer(min_len) and is_integer(max_len) and min_len >= 0 do
    unless min_len <= max_len do
      raise ArgumentError,
            "invalid {:string, min_len, max_len} schema: expected min_len <= max_len, " <>
              "got: #{min_len} > #{max_len}"
    end

    StreamData.string(:alphanumeric, min_length: min_len, max_length: max_len)
  end

  def from_schema({:enum, values}) when is_list(values) and values != [] do
    values
    |> Enum.map(&StreamData.constant/1)
    |> StreamData.one_of()
  end

  def from_schema({:list, schema}) do
    StreamData.list_of(from_schema(schema))
  end

  def from_schema({:list, schema, opts}) when is_list(opts) do
    min = Keyword.get(opts, :min, @default_min_length)
    max = Keyword.get(opts, :max, @default_max_length)

    validate_list_bounds!(min, max)

    StreamData.list_of(from_schema(schema), min_length: min, max_length: max)
  end

  def from_schema({:map, schema_map}) when is_map(schema_map) do
    schema_map
    |> Map.new(fn {key, value_schema} -> {key, from_schema(value_schema)} end)
    |> StreamData.fixed_map()
  end

  def from_schema({:optional, schema}) do
    StreamData.one_of([StreamData.constant(nil), from_schema(schema)])
  end

  def from_schema({:one_of, schemas}) when is_list(schemas) and schemas != [] do
    schemas
    |> Enum.map(&from_schema/1)
    |> StreamData.one_of()
  end

  def from_schema(other) do
    raise ArgumentError, "unsupported schema: #{inspect(other)}"
  end

  @spec validate_list_bounds!(term(), term()) :: :ok
  defp validate_list_bounds!(min, max) when is_integer(min) and is_integer(max) and min >= 0 do
    if min <= max do
      :ok
    else
      raise ArgumentError,
            "invalid {:list, schema, opts} schema: expected :min <= :max, got: #{min} > #{max}"
    end
  end

  defp validate_list_bounds!(min, max) do
    raise ArgumentError,
          "invalid {:list, schema, opts} schema: :min and :max must be non-negative " <>
            "integers, got: min=#{inspect(min)}, max=#{inspect(max)}"
  end
end