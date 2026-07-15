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
  Determines whether an aggregate's value can be `nil` in a response.

  This is deliberately *not* `include_nil?`. That option controls whether `nil`
  values in the **source** rows take part in the computation (e.g. whether a
  `count` counts related rows whose field is `nil`); it says nothing about
  whether the aggregate itself can return `nil`, and it defaults to `false`,
  which would type every aggregate as non-nullable.

  An aggregate falls back to a default when the relationship yields no rows, so
  nullability is exactly "is there a default to fall back to?". `count` defaults
  to `0`, `list` to `[]` and `exists` to `false`, so they are never `nil`; `avg`,
  `first`, `sum`, `min`, `max` and `custom` default to `nil`. An explicit
  `default` on the aggregate overrides the kind's default and makes it
  non-nullable.
  """
  def aggregate_allow_nil?(%Ash.Resource.Aggregate{} = aggregate) do
    is_nil(aggregate.default) and is_nil(kind_default(aggregate.kind))
  end

  # `Ash.Query.Aggregate.default_value/1` reports `nil` for `:exists`, but that
  # default is never reached: an exists aggregate is a boolean predicate, and the
  # data layer yields `false` — not `nil` — when nothing matches. Deriving
  # nullability from `default_value/1` alone would type every `exists` as
  # `boolean | null` and break every existing consumer of one.
  defp kind_default(:exists), do: false
  defp kind_default(kind), do: Ash.Query.Aggregate.default_value(kind)

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
