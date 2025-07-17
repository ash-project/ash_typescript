defmodule AshTypescript.Rpc.FieldParser do
  @moduledoc """
  Tree-based field parsing for building Ash load statements.

  Handles all field types including simple attributes, relationships,
  calculations, and embedded resources with a unified recursive approach.

  This module implements a streamlined architecture with extracted utilities
  for improved maintainability and reduced code duplication.
  """

  alias AshTypescript.Rpc.FieldParser.{Context, LoadBuilder}
  alias AshTypescript.FieldFormatter

  @doc """
  Main entry point for parsing requested fields into Ash-compatible select and load statements.

  Takes a list of field specifications and returns a tuple of {select_fields, load_statements, calculation_specs}
  where select_fields are simple attributes for Ash.Query.select/2, load_statements
  are loadable fields for Ash.Query.load/2, and calculation_specs contain field specifications
  for result processing.

  ## Examples

      iex> fields = ["id", "title", "displayName", %{"user" => ["name"]}]
      iex> parse_requested_fields(fields, MyApp.Todo, :camel_case)
      {[:id, :title], [:display_name, {:user, [:name]}], %{}}

      iex> fields = [%{"metadata" => ["category", "displayCategory"]}]
      iex> parse_requested_fields(fields, MyApp.Todo, :camel_case)
      {[], [{:metadata, [:display_category]}], %{}}
  """
  @spec parse_requested_fields(fields :: list(), resource :: module(), formatter :: atom()) ::
          {select_fields :: list(), load_statements :: list(), calculation_specs :: map()}
  def parse_requested_fields(fields, resource, formatter) do
    context = Context.new(resource, formatter)

    {select_fields, load_statements, calculation_specs} =
      Enum.reduce(fields, {[], [], %{}}, fn field, {select_acc, load_acc, calc_specs_acc} ->
        case process_field(field, context) do
          {:select, field_atom} ->
            {[field_atom | select_acc], load_acc, calc_specs_acc}

          {:load, load_statement} ->
            {select_acc, [load_statement | load_acc], calc_specs_acc}

          {:both, field_atom, load_statement} ->
            {[field_atom | select_acc], [load_statement | load_acc], calc_specs_acc}

          {:calculation_load, load_entry, field_specs} ->
            # Handle complex calculations with field specifications
            updated_calc_specs =
              if field_specs do
                # Extract calculation name from load entry
                calc_name =
                  case load_entry do
                    {name, _} -> name
                    name -> name
                  end

                Map.put(calc_specs_acc, calc_name, field_specs)
              else
                calc_specs_acc
              end

            {select_acc, [load_entry | load_acc], updated_calc_specs}

          {:union_field_selection, field_atom, union_member_specs} ->
            # Handle union field selection - select the union field and store member specs for result processing
            updated_calc_specs =
              Map.put(calc_specs_acc, field_atom, {:union_selection, union_member_specs})

            {[field_atom | select_acc], load_acc, updated_calc_specs}

          {:skip, _field_atom} ->
            # Skip unknown fields gracefully
            {select_acc, load_acc, calc_specs_acc}
        end
      end)

    {Enum.reverse(select_fields), Enum.reverse(load_statements), calculation_specs}
  end

  @doc """
  Process a single field using the unified pipeline.

  Returns one of:
  - {:select, field_atom} - Field should go to select list
  - {:load, load_statement} - Field should go to load list
  - {:both, field_atom, load_statement} - Field needs both select and load
  - {:calculation_load, load_entry, field_specs} - Complex calculation with specs
  - {:skip, field_atom} - Unknown field to skip
  """
  def process_field(field, %Context{} = context) do
    {field_atom, field_spec} = normalize_field(field, context)
    classify_and_process(field_atom, field_spec, context)
  end

  @doc """
  Normalize field input into consistent {field_atom, field_spec} format.
  """
  def normalize_field(field, %Context{} = context) when is_binary(field) do
    field_atom = FieldFormatter.parse_input_field(field, context.formatter)
    {field_atom, nil}
  end

  def normalize_field(field_map, %Context{} = context) when is_map(field_map) do
    case Map.to_list(field_map) do
      [{field_name, field_spec}] ->
        field_atom = FieldFormatter.parse_input_field(field_name, context.formatter)
        {field_atom, field_spec}

      _ ->
        # Invalid field specification - treat as unknown
        {field_map, nil}
    end
  end

  def normalize_field(field, _context) do
    # Unknown field format
    {field, nil}
  end

  @doc """
  Classify field and process according to its type.
  """
  def classify_and_process(field_atom, field_spec, %Context{} = context)
      when is_atom(field_atom) do
    case classify_field(field_atom, context.resource) do
      :simple_attribute ->
        {:select, field_atom}

      :simple_calculation ->
        {:load, field_atom}

      :complex_calculation when is_map(field_spec) ->
        # Complex calculation with arguments
        {load_entry, field_specs} =
          LoadBuilder.build_calculation_load_entry(field_atom, field_spec, context)

        {:calculation_load, load_entry, field_specs}

      :complex_calculation when is_list(field_spec) ->
        # Complex calculation with just field selection (no arguments)
        {:load, {field_atom, field_spec}}

      :complex_calculation ->
        # Complex calculation without arguments - load as simple calculation
        {:load, field_atom}

      :aggregate ->
        {:load, field_atom}

      :relationship when is_list(field_spec) ->
        target_resource = get_relationship_target_resource(field_atom, context.resource)

        nested_load =
          process_relationship_fields(field_atom, target_resource, field_spec, context.formatter)

        {:load, nested_load}

      :relationship ->
        # Relationship without nested fields - load the relationship itself
        {:load, field_atom}

      :embedded_resource when is_list(field_spec) ->
        # For embedded resources with nested field selection:
        # 1. Always SELECT the embedded attribute (for simple attributes)
        # 2. Parse nested fields to detect loadable items (calculations, relationships)
        embedded_module = get_embedded_resource_module(field_atom, context.resource)
        embedded_context = Context.child(context, embedded_module)

        embedded_load_items =
          process_embedded_fields(embedded_module, field_spec, embedded_context)

        case embedded_load_items do
          [] ->
            # No loadable items (calculations/relationships) - just select the embedded resource
            {:select, field_atom}

          load_items ->
            # Both simple attributes (via select) and loadable items (via load) requested
            {:both, field_atom, {field_atom, load_items}}
        end

      :embedded_resource ->
        # Embedded resource without nested fields - SELECT the embedded attribute
        # Embedded resources are attributes that should be selected, not loaded
        {:select, field_atom}

      :union_type when is_list(field_spec) ->
        # Union type with member field selection
        # Parse the union member specifications and generate proper load statement
        union_member_specs = parse_union_member_specifications(field_spec, field_atom, context)
        {:union_field_selection, field_atom, union_member_specs}

      :union_type ->
        # Union type without member field selection - SELECT the union attribute
        {:select, field_atom}

      :unknown ->
        # Unknown field - skip it to avoid Ash errors
        {:skip, field_atom}
    end
  end

  def classify_and_process(field_atom, _field_spec, _context) do
    # Non-atom field name - treat as unknown
    {:skip, field_atom}
  end

  @doc """
  Classify a field by its type within a resource.

  Returns one of: :simple_attribute, :simple_calculation, :complex_calculation, :aggregate,
  :relationship, :embedded_resource, :union_type, :unknown
  """
  def classify_field(field_name, resource) when is_atom(field_name) do
    cond do
      is_union_type_field?(field_name, resource) ->
        :union_type

      is_embedded_resource_field?(field_name, resource) ->
        :embedded_resource

      is_relationship?(field_name, resource) ->
        :relationship

      is_calculation?(field_name, resource) ->
        # Distinguish between simple and complex calculations
        calc_definition = get_calculation_definition(field_name, resource)

        if has_arguments?(calc_definition) do
          :complex_calculation
        else
          :simple_calculation
        end

      is_aggregate?(field_name, resource) ->
        :aggregate

      is_simple_attribute?(field_name, resource) ->
        :simple_attribute

      true ->
        :unknown
    end
  end

  @doc """
  Process nested fields for embedded resources.

  For embedded resources:
  - Simple attributes are automatically loaded when the embedded resource is selected
  - Only calculations and relationships need to be explicitly loaded
  - Field selection happens during result processing

  Returns a list of load statements for calculations and relationships only.
  """
  def process_embedded_fields(embedded_module, nested_fields, %Context{} = context) do
    # Process each nested field and collect only loadable items
    Enum.reduce(nested_fields, [], fn field, acc ->
      case process_embedded_field(field, embedded_module, context) do
        nil -> acc
        load_item -> [load_item | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp process_embedded_field(field_name, embedded_module, %Context{} = context)
       when is_binary(field_name) do
    field_atom = FieldFormatter.parse_input_field(field_name, context.formatter)

    case classify_field(field_atom, embedded_module) do
      :simple_calculation -> field_atom
      :aggregate -> field_atom
      :relationship -> field_atom
      :embedded_resource -> field_atom
      # Automatically included, skip
      :simple_attribute -> nil
      # Unknown field - skip for safety
      :unknown -> nil
    end
  end

  defp process_embedded_field(field_map, embedded_module, %Context{} = context)
       when is_map(field_map) do
    case Map.to_list(field_map) do
      [{field_name, nested_fields}] when is_binary(field_name) and is_list(nested_fields) ->
        field_atom = FieldFormatter.parse_input_field(field_name, context.formatter)

        case classify_field(field_atom, embedded_module) do
          :relationship ->
            # Relationship with nested fields
            target_resource = get_relationship_target_resource(field_atom, embedded_module)

            process_relationship_fields(
              field_atom,
              target_resource,
              nested_fields,
              context.formatter
            )

          :embedded_resource ->
            # Nested embedded resource with nested fields
            nested_embedded_module = get_embedded_resource_module(field_atom, embedded_module)
            nested_context = Context.child(context, nested_embedded_module)

            nested_load_items =
              process_embedded_fields(nested_embedded_module, nested_fields, nested_context)

            case nested_load_items do
              # No loadable items in nested embedded resource
              [] -> nil
              items -> {field_atom, items}
            end

          # Not a loadable complex field
          _ ->
            nil
        end

      [{field_name, calc_spec}] when is_binary(field_name) and is_map(calc_spec) ->
        # Handle complex calculation with calcArgs within embedded resource
        field_atom = FieldFormatter.parse_input_field(field_name, context.formatter)

        case classify_field(field_atom, embedded_module) do
          :complex_calculation ->
            # Complex calculation with arguments
            embedded_context = Context.child(context, embedded_module)

            {load_entry, _field_specs} =
              LoadBuilder.build_calculation_load_entry(field_atom, calc_spec, embedded_context)

            load_entry

          # Not a complex calculation
          _ ->
            nil
        end

      # Invalid field map format
      _ ->
        nil
    end
  end

  defp process_embedded_field(_field, _embedded_module, _context) do
    # Unknown field format
    nil
  end

  @doc """
  Process nested fields for relationships.

  Returns a load statement in the format {:relationship_name, nested_loads}.
  """
  def process_relationship_fields(relationship_name, target_resource, nested_fields, formatter) do
    # Recursively process nested fields using the relationship target resource
    {nested_select, nested_load, _nested_calc_specs} =
      parse_requested_fields(nested_fields, target_resource, formatter)

    # For relationships, combine select and load into a single nested load list
    combined_nested = nested_select ++ nested_load

    {relationship_name, combined_nested}
  end

  @doc """
  Filter load statements to only include calculations for embedded resources.

  For embedded resources, Ash automatically loads base attributes, so we only need
  to explicitly load calculations. This function filters out simple attributes
  from embedded resource load specifications.
  """
  def filter_embedded_load_for_ash(load_statements, resource) do
    load_statements
    |> Enum.map(fn
      {field_name, nested_fields} when is_atom(field_name) and is_list(nested_fields) ->
        case classify_field(field_name, resource) do
          :embedded_resource ->
            embedded_module = get_embedded_resource_module(field_name, resource)
            # Filter nested fields to only include calculations and aggregates
            loadable_only =
              Enum.filter(nested_fields, fn
                nested_field when is_atom(nested_field) ->
                  is_calculation?(nested_field, embedded_module) or
                    is_aggregate?(nested_field, embedded_module)

                _ ->
                  # Keep complex nested structures as-is
                  true
              end)

            # If no loadable items remain, return :skip to exclude from Ash load
            case loadable_only do
              # Will be filtered out in next step
              [] -> :skip
              loadable -> {field_name, loadable}
            end

          _ ->
            # Not an embedded resource, keep as-is
            {field_name, nested_fields}
        end

      other ->
        # Not a nested structure, keep as-is
        other
    end)
    # Remove skipped embedded resources with no calculations
    |> Enum.reject(&(&1 == :skip))
  end

  # Field type checking functions

  @doc "Check if a field is a simple attribute of the resource."
  def is_simple_attribute?(field_name, resource) when is_atom(field_name) do
    resource
    |> Ash.Resource.Info.public_attributes()
    |> Enum.any?(&(&1.name == field_name))
  end

  @doc "Check if a field is a relationship of the resource."
  def is_relationship?(field_name, resource) when is_atom(field_name) do
    resource
    |> Ash.Resource.Info.public_relationships()
    |> Enum.any?(&(&1.name == field_name))
  end

  @doc "Check if a field is an embedded resource attribute."
  def is_embedded_resource_field?(field_name, resource) when is_atom(field_name) do
    case Ash.Resource.Info.attribute(resource, field_name) do
      nil -> false
      attribute -> is_embedded_resource_type?(attribute.type)
    end
  end

  @doc "Check if a field is a calculation of the resource."
  def is_calculation?(field_name, resource) when is_atom(field_name) do
    resource
    |> Ash.Resource.Info.calculations()
    |> Enum.any?(&(&1.name == field_name))
  end

  @doc "Check if a field is an aggregate of the resource."
  def is_aggregate?(field_name, resource) when is_atom(field_name) do
    resource
    |> Ash.Resource.Info.aggregates()
    |> Enum.any?(&(&1.name == field_name))
  end

  @doc "Check if a field is a union type attribute."
  def is_union_type_field?(field_name, resource) when is_atom(field_name) do
    case Ash.Resource.Info.attribute(resource, field_name) do
      nil -> false
      attribute -> is_union_type?(attribute.type)
    end
  end

  @doc "Get the calculation definition for a field."
  def get_calculation_definition(field_name, resource) when is_atom(field_name) do
    resource
    |> Ash.Resource.Info.calculations()
    |> Enum.find(&(&1.name == field_name))
  end

  @doc "Check if a calculation definition has arguments."
  def has_arguments?(calc_definition) do
    calc_definition && length(calc_definition.arguments) > 0
  end

  @doc """
  Build a load statement based on field type.

  Backward compatibility function for existing tests.
  """
  def build_load_statement(:simple_calculation, field_name, _nested_data, _resource) do
    field_name
  end

  def build_load_statement(:relationship, field_name, nested_fields, _resource)
      when is_list(nested_fields) do
    {field_name, nested_fields}
  end

  def build_load_statement(:embedded_resource, field_name, nested_fields, _resource)
      when is_list(nested_fields) do
    {field_name, nested_fields}
  end

  def build_load_statement(_, field_name, _nested_data, _resource) do
    field_name
  end

  @doc """
  Parse union member specifications from field spec.

  Converts array like ["note", { text: ["id", "text"] }] into a map of member specifications
  that can be used during result processing to filter union member fields.
  """
  def parse_union_member_specifications(field_spec, field_atom, %Context{} = context)
      when is_list(field_spec) do
    union_attribute = Ash.Resource.Info.attribute(context.resource, field_atom)
    union_types = get_union_types_from_attribute(union_attribute)

    Enum.reduce(field_spec, %{}, fn member_spec, acc ->
      case member_spec do
        member_name when is_binary(member_name) ->
          # Primitive union member - just mark as included
          member_atom = String.to_atom(member_name)

          if Map.has_key?(union_types, member_atom) do
            Map.put(acc, member_name, :primitive)
          else
            # Skip unknown union members
            acc
          end

        member_map when is_map(member_map) ->
          # Complex union member with field selection
          case Map.to_list(member_map) do
            [{member_name, member_fields}]
            when is_binary(member_name) and is_list(member_fields) ->
              member_atom = String.to_atom(member_name)

              if Map.has_key?(union_types, member_atom) do
                # Store the field list for this union member
                Map.put(acc, member_name, member_fields)
              else
                # Skip unknown union members
                acc
              end

            _ ->
              # Skip invalid member specs
              acc
          end

        _ ->
          # Skip invalid member specs
          acc
      end
    end)
  end

  # Private helper functions

  defp is_embedded_resource_type?(module) when is_atom(module) do
    try do
      # Use the same detection logic as in the main codebase
      AshTypescript.Codegen.is_embedded_resource?(module)
    rescue
      _ -> false
    end
  end

  defp is_embedded_resource_type?({:array, module}) when is_atom(module) do
    is_embedded_resource_type?(module)
  end

  defp is_embedded_resource_type?(_), do: false

  defp is_union_type?(Ash.Type.Union), do: true
  defp is_union_type?({:array, Ash.Type.Union}), do: true
  defp is_union_type?(_), do: false

  defp get_union_types_from_attribute(%{type: Ash.Type.Union, constraints: constraints}) do
    constraints
    |> Keyword.get(:types, [])
    |> Enum.into(%{})
  end

  defp get_union_types_from_attribute(%{type: {:array, Ash.Type.Union}, constraints: constraints}) do
    constraints
    |> Keyword.get(:items, [])
    |> Keyword.get(:types, [])
    |> Enum.into(%{})
  end

  defp get_union_types_from_attribute(_), do: %{}

  defp get_relationship_target_resource(relationship_name, resource) do
    resource
    |> Ash.Resource.Info.public_relationships()
    |> Enum.find(&(&1.name == relationship_name))
    |> case do
      # Fallback to same resource
      nil -> resource
      relationship -> relationship.destination
    end
  end

  defp get_embedded_resource_module(field_name, resource) do
    case Ash.Resource.Info.attribute(resource, field_name) do
      nil ->
        nil

      attribute ->
        case attribute.type do
          module when is_atom(module) -> module
          {:array, module} when is_atom(module) -> module
          _ -> nil
        end
    end
  end

end
