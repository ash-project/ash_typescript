# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
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
    has_arguments = !Enum.empty?(calc.arguments)
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

  # Sort the `:fields` entry of a typed-map/struct constraint list
  # alphabetically by key.
  #
  # Why: `:auto`-typed calcs use Ash's expression-to-type resolver, which
  # materializes literal map exprs (`expr(%{a: id, b: name})`) through a
  # runtime Erlang map. Map iteration order depends on atom term ordering,
  # which varies between BEAM loads (e.g. warm `_build/dev` vs clean
  # `_build/test`). Left unsorted, the emitted TypeScript would reshuffle
  # across compiles. TS field order is cosmetic, so alphabetical is fine.
  #
  # How to apply: call only on constraints derived from an `:auto` calc
  # (calcs whose `calculation` is `Ash.Resource.Calculation.Expression`, or
  # publications whose `transform:` resolves to such a calc). Other
  # `:fields` lists come from user DSL and already have a stable order.
  def sort_auto_fields(constraints) when is_list(constraints) do
    case Keyword.fetch(constraints, :fields) do
      {:ok, fields} when is_list(fields) ->
        sorted = Enum.sort_by(fields, fn {name, _} -> Atom.to_string(name) end)
        Keyword.put(constraints, :fields, sorted)

      _ ->
        constraints
    end
  end

  def sort_auto_fields(constraints), do: constraints

  # Returns `calc.constraints` with `:fields` sorted when the calculation
  # is expression-based (the only source of non-deterministic map-literal
  # field ordering). For all other calcs, returns constraints unchanged.
  def auto_safe_calc_constraints(
        %Ash.Resource.Calculation{
          calculation: {Ash.Resource.Calculation.Expression, _}
        } = calc
      ) do
    sort_auto_fields(calc.constraints || [])
  end

  def auto_safe_calc_constraints(%Ash.Resource.Calculation{} = calc) do
    calc.constraints || []
  end

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

  @doc """
  Converts a PascalCase name to camelCase by lowercasing the first character.

  ## Examples

      iex> AshTypescript.Codegen.Helpers.camel_case_prefix("Todo")
      "todo"

      iex> AshTypescript.Codegen.Helpers.camel_case_prefix("OrgTodo")
      "orgTodo"
  """
  def camel_case_prefix(<<first::utf8, rest::binary>>) do
    String.downcase(<<first::utf8>>) <> rest
  end

  @doc """
  Returns formatted client field names for a resource's public fields.

  Collects public attributes, calculations (with `field?: true`), and
  aggregates. Optionally includes relationships when `include_relationships: true`.

  Field names are formatted using the configured output formatter.
  """
  def client_field_names(resource, opts \\ []) do
    include_rels = Keyword.get(opts, :include_relationships, false)
    formatter = AshTypescript.Rpc.output_field_formatter()

    attrs =
      resource
      |> Ash.Resource.Info.public_attributes()
      |> Enum.map(& &1.name)

    calcs =
      resource
      |> Ash.Resource.Info.public_calculations()
      |> Enum.filter(fn calc -> Map.get(calc, :field?, true) end)
      |> Enum.map(& &1.name)

    aggs =
      resource
      |> Ash.Resource.Info.public_aggregates()
      |> Enum.map(& &1.name)

    rels =
      if include_rels do
        resource
        |> Ash.Resource.Info.public_relationships()
        |> Enum.map(& &1.name)
      else
        []
      end

    (attrs ++ calcs ++ aggs ++ rels)
    |> Enum.map(&AshTypescript.FieldFormatter.format_field_for_client(&1, resource, formatter))
  end
end
