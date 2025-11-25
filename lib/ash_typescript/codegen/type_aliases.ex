# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.TypeAliases do
  @moduledoc """
  Generates TypeScript type aliases for Ash types (e.g., UUID, Decimal, DateTime, etc.).
  """

  alias AshTypescript.Codegen.{Helpers, TypeDiscovery}
  alias AshTypescript.TypeSystem.Introspection

  @doc """
  Generates TypeScript type aliases for all Ash types used in resources, actions, and calculations.
  """
  def generate_ash_type_aliases(resources, actions, otp_app) do
    embedded_resources = TypeDiscovery.find_embedded_resources(otp_app)
    all_resources = resources ++ embedded_resources

    resource_types =
      Enum.reduce(all_resources, MapSet.new(), fn resource, types ->
        types =
          resource
          |> Ash.Resource.Info.public_attributes()
          |> Enum.reduce(types, fn attr, types -> MapSet.put(types, attr.type) end)

        types =
          resource
          |> Ash.Resource.Info.public_calculations()
          |> Enum.reduce(types, fn calc, types ->
            # Add the calculation's return type
            types = MapSet.put(types, calc.type)

            # Also add types from calculation arguments
            Enum.reduce(calc.arguments, types, fn arg, types ->
              if Ash.Type.ash_type?(arg.type) do
                MapSet.put(types, arg.type)
              else
                types
              end
            end)
          end)

        resource
        |> Ash.Resource.Info.public_aggregates()
        |> Enum.reduce(types, fn agg, types ->
          type =
            case agg.kind do
              :sum ->
                resource
                |> Helpers.lookup_aggregate_type(agg.relationship_path, agg.field)

              :first ->
                resource
                |> Helpers.lookup_aggregate_type(agg.relationship_path, agg.field)

              _ ->
                agg.kind
            end

          if Ash.Type.ash_type?(type) do
            MapSet.put(types, type)
          else
            types
          end
        end)
      end)

    types =
      Enum.reduce(actions, resource_types, fn action, types ->
        types =
          action.arguments
          |> Enum.reduce(types, fn argument, types ->
            if Ash.Type.ash_type?(argument.type) do
              MapSet.put(types, argument.type)
            else
              types
            end
          end)

        if action.type == :action do
          if Ash.Type.ash_type?(action.returns) do
            case action.returns do
              {:array, type} -> MapSet.put(types, type)
              _ -> MapSet.put(types, action.returns)
            end
          else
            types
          end
        else
          types
        end
      end)

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

      is_custom_type?(type) ->
        ""

      Ash.Type.NewType.new_type?(type) or Spark.implements_behaviour?(type, Ash.Type.Enum) ->
        ""

      Introspection.is_embedded_resource?(type) ->
        ""

      true ->
        raise "Unknown type: #{type}"
    end
  end

  defp is_custom_type?(type) do
    is_atom(type) and
      Code.ensure_loaded?(type) and
      function_exported?(type, :typescript_type_name, 0) and
      Spark.implements_behaviour?(type, Ash.Type)
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
