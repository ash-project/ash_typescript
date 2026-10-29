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
    * a `map` with no fields for a module that isn't a field-bearing NewType
      (an `Ash.TypedStruct`, or a NewType over `:map`, `:keyword`, `:tuple`
      or `:struct` with `fields`), or with a field name declared twice;
    * a `map` with fields for a field-bearing NewType: its fields come from
      the type, and a field-less entry opts it into an alias;
    * a field-less `map` with `zod` or `valibot`, which it would never use;
    * a field-less `map` entry for a module exporting `typescript_type/0`
      (a field-bearing NewType's TypeScript comes from its fields);
    * a `scalar` whose base type isn't an Ash type, or a `field` whose type is
      neither an Ash type nor a module with an entry (declared or built-in);
    * constraints the type rejects (`Ash.Type.init/2`). A field typed by a
      module with a `scalar` entry is checked against the scalar's base type,
      with its constraints merged over the scalar's (`Keyword.merge/2`, the
      field winning per key). A field typed by a `map` entry isn't checked;
    * a `ts_alias` string (`map` or `scalar`) that isn't a TypeScript
      identifier, or is a reserved word (`string`, `object`, `default`, …;
      `AshTypescript.CustomTypes.check_name/2`);
    * a `scalar` with an MFA `ts_alias` and a `ts_type` that isn't an MFA
      (or none).

  The persisted constraints are the user's (regexes already converted by the
  entity transforms), merged for scalar-typed fields. `Ash.Type.init/2` only
  validates them.
  """

  use Spark.Dsl.Transformer

  alias AshTypescript.CustomTypes
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
      with :ok <- init(scalar, path, scalar.type, scalar.constraints, inspect(scalar.module)),
           :ok <- check_scalar_ts_alias(scalar) do
        {:ok, scalar}
      end
    else
      {:error,
       {scalar, path,
        "The base type #{inspect(scalar.type)} of #{inspect(scalar.module)} is not an Ash type."}}
    end
  end

  # A field-less entry opts a field-bearing NewType into an alias.
  defp normalize(%MapType{fields: []} = map, _by_module) do
    if CustomTypes.field_bearing_new_type_module?(map.module) do
      with :ok <- check_no_schemas(map),
           :ok <- check_ts_alias(map),
           :ok <- check_no_type_callback(map) do
        {:ok, map}
      end
    else
      {:error,
       {map, [:map, map.module],
        "The map #{inspect(map.module)} needs at least one field (a field-less `map` entry " <>
          "is only for an `Ash.Type.NewType` with fields, such as an `Ash.TypedStruct`)."}}
    end
  end

  defp normalize(%MapType{} = map, by_module) do
    with :ok <- check_fields_not_from_type(map),
         :ok <- check_duplicate_fields(map),
         {:ok, fields} <- map_ok(map.fields, &normalize_field(map, &1, by_module)),
         :ok <- check_ts_alias(map) do
      {:ok, %{map | fields: fields}}
    end
  end

  defp check_scalar_ts_alias(%Scalar{ts_alias: nil}), do: :ok

  defp check_scalar_ts_alias(%Scalar{ts_alias: name} = scalar) when is_binary(name) do
    subject = "The ts_alias #{inspect(name)} of #{inspect(scalar.module)}"

    with {:error, message} <- CustomTypes.check_name(name, subject),
         do: {:error, {scalar, [:scalar, scalar.module, :ts_alias], message}}
  end

  defp check_scalar_ts_alias(%Scalar{ts_type: {_m, _f, _a}}), do: :ok

  defp check_scalar_ts_alias(%Scalar{} = scalar) do
    {:error,
     {scalar, [:scalar, scalar.module, :ts_alias],
      "#{inspect(scalar.module)}: an MFA `ts_alias` needs an MFA `ts_type`: both must be " <>
        "computed from the use's constraints."}}
  end

  # A field-less entry declares nothing, so a `zod` / `valibot` replacement on
  # it would be ignored.
  defp check_no_schemas(%MapType{} = map) do
    case Enum.find([:zod, :valibot], &Map.fetch!(map, &1)) do
      nil ->
        :ok

      option ->
        {:error,
         {map, [:map, map.module, option],
          "The `map` entry of #{inspect(map.module)} has no fields, so its `#{option}` would " <>
            "never be used; remove it (its schemas are generated from the type)."}}
    end
  end

  defp check_fields_not_from_type(%MapType{} = map) do
    if CustomTypes.field_bearing_new_type_module?(map.module) do
      {:error,
       {map, [:map, map.module],
        "The fields of #{inspect(map.module)} come from the type; remove them from its " <>
          "`map` entry."}}
    else
      :ok
    end
  end

  # A field-less `map` entry (an explicit alias opt-in) on a field-bearing
  # NewType that names its own TypeScript type. The callback opt-in
  # (`typescript_type_alias/0`) is checked by `DecorateManifest`
  # (`CustomTypes.check_alias_names/2`). A scalar combines
  # `typescript_type/0` with any opt-in: it is the alias body.
  defp check_no_type_callback(%MapType{} = map) do
    if exports_type?(map.module),
      do: {:error, {map, [:map, map.module], CustomTypes.type_callback_message(map.module)}},
      else: :ok
  end

  defp exports_type?(module),
    do: Code.ensure_loaded?(module) and function_exported?(module, :typescript_type, 0)

  defp check_ts_alias(%MapType{ts_alias: nil}), do: :ok

  defp check_ts_alias(%MapType{ts_alias: name} = map) do
    subject = "The ts_alias #{inspect(name)} of #{inspect(map.module)}"

    with {:error, message} <- CustomTypes.check_name(name, subject),
         do: {:error, {map, [:map, map.module, :ts_alias], message}}
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

    case CustomTypes.resolve_field_type(field.type, field.constraints, &Map.get(by_module, &1)) do
      {:ok, base, constraints} ->
        with :ok <- init(field, path, base, constraints, subject) do
          {:ok, %{field | constraints: constraints}}
        end

      # A field typed by a `map` entry isn't checked.
      :map ->
        {:ok, field}

      {:error, type} ->
        {:error,
         {field, path,
          "The type #{inspect(type)} of #{subject} is not an Ash type and has no scalar or map entry."}}
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
