# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.TypeAliases do
  @moduledoc """
  Generates TypeScript type aliases for Ash types (e.g., UUID, Decimal, DateTime, etc.).
  """

  @doc """
  Generates TypeScript type aliases for all Ash types used in resources, actions, and calculations.
  """
  def generate_ash_type_aliases(resources, actions, otp_app, resource_lookup \\ nil)

  def generate_ash_type_aliases(resources, _actions, _otp_app, resource_lookup)
      when is_map(resource_lookup) and map_size(resource_lookup) > 0 do
    # Derive embedded resources from resource_lookup instead of re-scanning
    embedded_resources =
      resource_lookup
      |> Map.values()
      |> Enum.filter(& &1.embedded?)
      |> Enum.map(& &1.module)

    all_resources = Enum.uniq(resources ++ embedded_resources)

    # Collect all types from spec resources (fields + action arguments + returns)
    types =
      Enum.reduce(all_resources, MapSet.new(), fn resource, types ->
        case Map.get(resource_lookup, resource) do
          %AshApiSpec.Resource{} = api_resource ->
            types = collect_types_from_api_resource(api_resource, types)
            collect_types_from_api_actions(api_resource, types)

          nil ->
            raise "TypeAliases: resource #{inspect(resource)} not found in resource_lookup"
        end
      end)

    generate_aliases(types)
  end

  def generate_ash_type_aliases(resources, _actions, otp_app, _no_lookup) do
    {:ok, api_spec} = AshApiSpec.Generator.generate(otp_app: otp_app)
    resource_lookup = AshApiSpec.resource_lookup(api_spec)

    generate_ash_type_aliases(resources, [], otp_app, resource_lookup)
  end

  defp collect_types_from_api_resource(api_resource, types) do
    api_resource.fields
    |> Map.values()
    |> Enum.reduce(types, fn field, types ->
      # Collect the field's type module
      types = collect_type_module(field.type, types)

      # For calculations with arguments, collect argument types
      if field.kind == :calculation && is_list(field.arguments) do
        Enum.reduce(field.arguments, types, fn arg, types ->
          arg_type = arg.type

          type_module =
            case arg_type do
              %AshApiSpec.Type{module: m} when is_atom(m) -> m
              _ -> nil
            end

          if type_module && Ash.Type.ash_type?(type_module) do
            MapSet.put(types, type_module)
          else
            types
          end
        end)
      else
        types
      end
    end)
  end

  defp collect_type_module(%AshApiSpec.Type{kind: :array, item_type: item_type}, types) do
    collect_type_module(item_type, types)
  end

  defp collect_type_module(%AshApiSpec.Type{module: module}, types)
       when is_atom(module) and not is_nil(module) do
    if Ash.Type.ash_type?(module) do
      MapSet.put(types, module)
    else
      types
    end
  end

  defp collect_type_module(_, types), do: types

  # Collects type modules from spec action arguments and returns
  defp collect_types_from_api_actions(api_resource, types) do
    api_resource.actions
    |> Map.values()
    |> Enum.reduce(types, fn action, types ->
      # Collect from action arguments
      types =
        Enum.reduce(action.arguments || [], types, fn arg, types ->
          collect_type_module(arg.type, types)
        end)

      # Collect from action returns (for generic actions)
      case action.returns do
        %AshApiSpec.Type{} = return_type -> collect_type_module(return_type, types)
        _ -> types
      end
    end)
  end

  defp generate_aliases(types) do
    types
    |> Enum.map(fn type ->
      case type do
        {:array, type} -> type
        type -> type
      end
    end)
    |> Enum.uniq()
    |> Enum.map(&generate_ash_type_alias/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.sort()
    |> Enum.join("\n")
  end

  # Primitive types that don't need aliases
  defp generate_ash_type_alias(Ash.Type.Struct), do: ""
  defp generate_ash_type_alias(Ash.Type.Union), do: ""
  defp generate_ash_type_alias(Ash.Type.Atom), do: ""
  defp generate_ash_type_alias(Ash.Type.Boolean), do: ""
  defp generate_ash_type_alias(Ash.Type.Integer), do: ""
  defp generate_ash_type_alias(Ash.Type.Float), do: ""
  defp generate_ash_type_alias(Ash.Type.Map), do: ""
  defp generate_ash_type_alias(Ash.Type.Keyword), do: ""
  defp generate_ash_type_alias(Ash.Type.Tuple), do: ""
  defp generate_ash_type_alias(Ash.Type.String), do: ""
  defp generate_ash_type_alias(Ash.Type.CiString), do: ""

  # Types that need TypeScript aliases
  defp generate_ash_type_alias(Ash.Type.UUID), do: "export type UUID = string;"
  defp generate_ash_type_alias(Ash.Type.UUIDv7), do: "export type UUIDv7 = string;"
  defp generate_ash_type_alias(Ash.Type.Decimal), do: "export type Decimal = string;"
  defp generate_ash_type_alias(Ash.Type.Date), do: "export type AshDate = string;"
  defp generate_ash_type_alias(Ash.Type.Time), do: "export type Time = string;"
  defp generate_ash_type_alias(Ash.Type.TimeUsec), do: "export type TimeUsec = string;"
  defp generate_ash_type_alias(Ash.Type.UtcDatetime), do: "export type UtcDateTime = string;"

  defp generate_ash_type_alias(Ash.Type.UtcDatetimeUsec),
    do: "export type UtcDateTimeUsec = string;"

  defp generate_ash_type_alias(Ash.Type.DateTime), do: "export type DateTime = string;"
  defp generate_ash_type_alias(Ash.Type.NaiveDatetime), do: "export type NaiveDateTime = string;"
  defp generate_ash_type_alias(Ash.Type.Duration), do: "export type Duration = string;"
  defp generate_ash_type_alias(Ash.Type.DurationName), do: "export type DurationName = string;"
  defp generate_ash_type_alias(Ash.Type.Binary), do: "export type Binary = string;"

  defp generate_ash_type_alias(Ash.Type.UrlEncodedBinary),
    do: "export type UrlEncodedBinary = string;"

  defp generate_ash_type_alias(Ash.Type.File), do: "export type File = any;"
  defp generate_ash_type_alias(Ash.Type.Function), do: "export type Function = any;"
  defp generate_ash_type_alias(Ash.Type.Module), do: "export type ModuleName = string;"
  defp generate_ash_type_alias(AshDoubleEntry.ULID), do: "export type ULID = string;"

  defp generate_ash_type_alias(AshPostgres.Ltree),
    do:
      "export type AshPostgresLtreeFlexible = string | string[];\nexport type AshPostgresLtreeArray = string[];"

  defp generate_ash_type_alias(AshMoney.Types.Money),
    do: "export type Money = { amount: string; currency: string };"

  defp generate_ash_type_alias(type) do
    cond do
      get_type_mapping_override(type) != nil ->
        ""

      AshTypescript.TypeSystem.Introspection.is_custom_type?(type) ->
        ""

      Ash.Type.NewType.new_type?(type) or Spark.implements_behaviour?(type, Ash.Type.Enum) ->
        ""

      is_atom(type) and not is_nil(type) and Ash.Resource.Info.resource?(type) and
          Ash.Resource.Info.embedded?(type) ->
        ""

      true ->
        raise "Unknown type: #{type}"
    end
  end

  defp get_type_mapping_override(type) when is_atom(type) do
    type_mapping_overrides = AshTypescript.type_mapping_overrides()

    case List.keyfind(type_mapping_overrides, type, 0) do
      {^type, ts_type} -> ts_type
      nil -> nil
    end
  end

  defp get_type_mapping_override(_type), do: nil
end
