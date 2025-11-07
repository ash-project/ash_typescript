# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.Helpers do
  @moduledoc """
  Shared helper functions for code generation.
  """

  @doc """
  Builds a TypeScript type name from a resource module.
  Uses the custom typescript_type_name if defined, otherwise derives from module name.
  """
  def build_resource_type_name(resource_module) do
    case AshTypescript.Resource.Info.typescript_type_name(resource_module) do
      {:ok, name} ->
        name

      _ ->
        resource_module
        |> Module.split()
        |> then(fn [first | rest] = list ->
          if first == "Elixir" do
            Enum.join(rest, "")
          else
            Enum.join(list, "")
          end
        end)
    end
  end

  @doc """
  Determines if a calculation is simple (no arguments, no complex return type).
  Simple calculations are treated like regular fields in the schema.
  """
  def is_simple_calculation(%Ash.Resource.Calculation{} = calc) do
    has_arguments = length(calc.arguments) > 0
    has_complex_return_type = is_complex_return_type(calc.type, calc.constraints)

    not has_arguments and not has_complex_return_type
  end

  @doc """
  Determines if a return type is complex (requires special metadata handling).
  """
  def is_complex_return_type(Ash.Type.Struct, constraints) do
    instance_of = Keyword.get(constraints, :instance_of)
    instance_of != nil
  end

  def is_complex_return_type(Ash.Type.Map, constraints) do
    fields = Keyword.get(constraints, :fields)
    fields != nil
  end

  def is_complex_return_type(Ash.Type.Keyword, _constraints), do: true
  def is_complex_return_type(Ash.Type.Tuple, _constraints), do: true
  def is_complex_return_type(_, _), do: false

  @doc """
  Looks up the type of an aggregate field by traversing relationship paths.
  """
  def lookup_aggregate_type(current_resource, [], field) do
    Ash.Resource.Info.attribute(current_resource, field)
  end

  def lookup_aggregate_type(current_resource, relationship_path, field) do
    [next_resource | rest] = relationship_path

    relationship =
      Enum.find(Ash.Resource.Info.relationships(current_resource), &(&1.name == next_resource))

    lookup_aggregate_type(relationship.destination, rest, field)
  end
end
