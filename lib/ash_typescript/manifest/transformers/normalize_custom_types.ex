# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.Transformers.NormalizeCustomTypes do
  @moduledoc """
  Validates the manifest module's `custom_types` section and persists it,
  with the built-in entries, as `:custom_types`:
  `%{declared: %{module => entry}, builtin: %{module => entry}}`.

  Runs before `BuildManifest`. It rejects, with a `Spark.Error.DslError`:

    * a module declared more than once;
    * a `map` with no fields, or with a field name declared twice;
    * a `scalar` whose base type isn't an Ash type, or a `field` whose type is
      neither an Ash type nor a module with an entry (declared or built-in);
    * constraints the type rejects (`Ash.Type.init/2`). A field typed by a
      module with a `scalar` entry is checked against the scalar's base type,
      with its constraints merged over the scalar's (`Keyword.merge/2`, the
      field winning per key). A field typed by a `map` entry isn't checked.

  The persisted constraints are the user's (regexes already converted by the
  entity transforms), merged for scalar-typed fields. `Ash.Type.init/2` only
  validates them.
  """

  use Spark.Dsl.Transformer

  alias AshTypescript.CustomTypes.{Builtin, Field, MapType, Scalar}
  alias Spark.Dsl.Transformer

  @impl true
  def before?(AshTypescript.Manifest.Transformers.BuildManifest), do: true
  def before?(_), do: false

  @impl true
  def transform(dsl_state) do
    module = Transformer.get_persisted(dsl_state, :module)
    entries = Transformer.get_entities(dsl_state, [:custom_types])
    builtin = Builtin.by_module()

    with :ok <- check_duplicates(entries),
         declared = Map.new(entries, &{&1.module, &1}),
         {:ok, normalized} <- normalize_all(entries, Map.merge(builtin, declared)) do
      {:ok,
       Transformer.persist(dsl_state, :custom_types, %{
         declared: Map.new(normalized, &{&1.module, &1}),
         builtin: builtin
       })}
    else
      {:error, {entry, path, message}} ->
        {:error,
         Spark.Error.DslError.exception(
           module: module,
           path: [:custom_types | path],
           message: message,
           location: Spark.Dsl.Entity.anno(entry)
         )}
    end
  end

  defp check_duplicates(entries) do
    entries
    |> Enum.group_by(& &1.module)
    |> Enum.find(fn {_module, group} -> length(group) > 1 end)
    |> case do
      nil ->
        :ok

      {module, [_, second | _]} ->
        {:error,
         {second, [entity_name(second), module],
          "#{inspect(module)} is declared more than once. Each module may appear once in custom_types."}}
    end
  end

  defp normalize_all(entries, by_module), do: map_ok(entries, &normalize(&1, by_module))

  defp normalize(%Scalar{} = scalar, _by_module) do
    path = [:scalar, scalar.module]

    if Ash.Type.ash_type?(scalar.type) do
      with :ok <- init(scalar, path, scalar.type, scalar.constraints, inspect(scalar.module)) do
        {:ok, scalar}
      end
    else
      {:error,
       {scalar, path,
        "The base type #{inspect(scalar.type)} of #{inspect(scalar.module)} is not an Ash type."}}
    end
  end

  defp normalize(%MapType{fields: []} = map, _by_module) do
    {:error,
     {map, [:map, map.module], "The map #{inspect(map.module)} needs at least one field."}}
  end

  defp normalize(%MapType{} = map, by_module) do
    with :ok <- check_duplicate_fields(map),
         {:ok, fields} <- map_ok(map.fields, &normalize_field(map, &1, by_module)) do
      {:ok, %{map | fields: fields}}
    end
  end

  defp check_duplicate_fields(%MapType{} = map) do
    map.fields
    |> Enum.group_by(& &1.name)
    |> Enum.find(fn {_name, group} -> length(group) > 1 end)
    |> case do
      nil ->
        :ok

      {name, [_, second | _]} ->
        {:error,
         {second, [:map, map.module, :field, name],
          "The field #{inspect(name)} of #{inspect(map.module)} is declared more than once."}}
    end
  end

  defp normalize_field(%MapType{} = map, %Field{} = field, by_module) do
    path = [:map, map.module, :field, field.name]
    subject = "field #{inspect(field.name)} of #{inspect(map.module)}"

    case resolve(field.type, field.constraints, by_module) do
      {:ok, base, constraints} ->
        with :ok <- init(field, path, base, constraints, subject) do
          {:ok, %{field | constraints: constraints}}
        end

      :unchecked ->
        {:ok, field}

      {:error, type} ->
        {:error,
         {field, path,
          "The type #{inspect(type)} of #{subject} is not an Ash type and has no scalar or map entry."}}
    end
  end

  # The type to validate `constraints` against and the constraints to persist:
  # a declared scalar resolves to its base type, its constraints merged under
  # the field's; a `map` entry isn't checked.
  defp resolve({:array, inner}, constraints, by_module) do
    case resolve(inner, Keyword.get(constraints, :items, []), by_module) do
      {:ok, base, []} -> {:ok, {:array, base}, constraints}
      {:ok, base, items} -> {:ok, {:array, base}, Keyword.put(constraints, :items, items)}
      other -> other
    end
  end

  defp resolve(type, constraints, by_module) do
    case Map.get(by_module, type) do
      %Scalar{} = scalar -> {:ok, scalar.type, Keyword.merge(scalar.constraints, constraints)}
      %MapType{} -> :unchecked
      nil -> if Ash.Type.ash_type?(type), do: {:ok, type, constraints}, else: {:error, type}
    end
  end

  defp init(entry, path, type, constraints, subject) do
    case Ash.Type.init(type, constraints) do
      {:ok, _} ->
        :ok

      # `init/2` reports invalid constraints as a formatted string.
      {:error, message} ->
        {:error,
         {entry, path, "Invalid constraints for #{subject} (#{inspect(type)}): #{message}"}}
    end
  end

  # Maps `fun` over `list`, stopping at the first `{:error, _}`.
  defp map_ok(list, fun) do
    Enum.reduce_while(list, {:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, item} -> {:cont, {:ok, [item | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  defp entity_name(%Scalar{}), do: :scalar
  defp entity_name(%MapType{}), do: :map
end
