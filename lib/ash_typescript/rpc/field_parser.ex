defmodule AshTypescript.Rpc.FieldParser do
  @moduledoc """
  Tree-based field parsing for building Ash load statements.

  Handles all field types including simple attributes, relationships,
  calculations, and embedded resources with a unified recursive approach.

  This module implements a streamlined architecture with extracted utilities
  for improved maintainability and reduced code duplication.
  """

  alias AshTypescript.Rpc.FieldParser.{Context, LoadBuilder}
  alias AshTypescript.Rpc.ExtractionTemplate
  alias AshTypescript.FieldFormatter

  @doc """
  Main entry point for parsing requested fields into Ash-compatible select and load statements.

  Takes a list of field specifications and returns a tuple of {select_fields, load_statements, extraction_template}
  where select_fields are simple attributes for Ash.Query.select/2, load_statements
  are loadable fields for Ash.Query.load/2, and extraction_template contains pre-computed
  instructions for result extraction and formatting.

  ## Examples

      iex> fields = ["id", "title", "displayName", %{"user" => ["name"]}]
      iex> parse_requested_fields(fields, MyApp.Todo, :camel_case)
      {[:id, :title], [:display_name, {:user, [:name]}], %{"id" => {:extract, :id}, "title" => {:extract, :title}, "user" => {:nested, :user, %{"name" => {:extract, :name}}}}}

      iex> fields = [%{"metadata" => ["category", "displayCategory"]}]
      iex> parse_requested_fields(fields, MyApp.Todo, :camel_case)
      {[], [{:metadata, [:display_category]}], %{"metadata" => {:nested, :metadata, %{"category" => {:extract, :category}, "displayCategory" => {:extract, :display_category}}}}}
  """
  @spec parse_requested_fields(fields :: list(), resource :: module(), formatter :: atom()) ::
          {select_fields :: list(), load_statements :: list(), extraction_template :: ExtractionTemplate.extraction_template()}
  def parse_requested_fields(fields, resource, formatter) do
    context = Context.new(resource, formatter)

    {select_fields, load_statements, extraction_template} =
      Enum.reduce(fields, {[], [], ExtractionTemplate.new()}, fn field, {select_acc, load_acc, template_acc} ->
        # Handle maps with multiple entries (e.g., multiple TypedStruct field selections)
        case field do
          field_map when is_map(field_map) and map_size(field_map) > 1 ->
            # Process each entry in the map as a separate field
            Enum.reduce(field_map, {select_acc, load_acc, template_acc}, fn {field_name,
                                                                               field_spec},
                                                                              acc ->
              process_single_field({field_name, field_spec}, context, acc)
            end)

          _ ->
            # Process single field normally
            process_single_field(field, context, {select_acc, load_acc, template_acc})
        end
      end)

    {Enum.reverse(select_fields), Enum.reverse(load_statements), extraction_template}
  end

  # Process a single field and update accumulators
  defp process_single_field(field, context, {select_acc, load_acc, template_acc}) do
    case process_field(field, context) do
      {:select, field_atom} ->
        # Generate extraction instruction for simple field
        output_field = format_output_field_name(field_atom, context.formatter)
        instruction = ExtractionTemplate.extract_field(field_atom)
        updated_template = ExtractionTemplate.put_instruction(template_acc, output_field, instruction)
        {[field_atom | select_acc], load_acc, updated_template}

      {:load, load_statement} ->
        # Load statement - could be simple or nested
        field_atom = extract_field_atom_from_load_statement(load_statement)
        output_field = format_output_field_name(field_atom, context.formatter)
        
        instruction = case load_statement do
          {^field_atom, nested_fields} when is_list(nested_fields) ->
            # Nested relationship or embedded resource - build nested template
            target_resource = determine_target_resource_for_field(field_atom, context.resource)
            nested_template = build_nested_extraction_template_for_resource(nested_fields, target_resource, context.formatter)
            ExtractionTemplate.nested_field(field_atom, nested_template)
          
          _ ->
            # Simple load - just extract the field
            ExtractionTemplate.extract_field(field_atom)
        end
        
        updated_template = ExtractionTemplate.put_instruction(template_acc, output_field, instruction)
        {select_acc, [load_statement | load_acc], updated_template}


      {:calculation_load, load_entry, field_specs} ->
        # Handle complex calculations with field specifications
        field_atom = extract_field_atom_from_load_statement(load_entry)
        output_field = format_output_field_name(field_atom, context.formatter)
        
        instruction = if field_specs do
          # Build nested template for calculation result
          field_template = build_nested_extraction_template(field_specs, context)
          ExtractionTemplate.calc_result_field(field_atom, field_template)
        else
          # Simple calculation without field selection
          ExtractionTemplate.extract_field(field_atom)
        end
        
        updated_template = ExtractionTemplate.put_instruction(template_acc, output_field, instruction)
        {select_acc, [load_entry | load_acc], updated_template}

      {:union_field_selection, field_atom, union_member_specs} ->
        # Handle union field selection - generate union selection instruction
        output_field = format_output_field_name(field_atom, context.formatter)
        instruction = ExtractionTemplate.union_selection_field(field_atom, union_member_specs)
        updated_template = ExtractionTemplate.put_instruction(template_acc, output_field, instruction)
        {[field_atom | select_acc], load_acc, updated_template}

      {:typed_struct_selection, field_atom, field_specs} ->
        # Handle TypedStruct field selection - generate typed struct selection instruction
        output_field = format_output_field_name(field_atom, context.formatter)
        instruction = ExtractionTemplate.typed_struct_selection_field(field_atom, field_specs)
        updated_template = ExtractionTemplate.put_instruction(template_acc, output_field, instruction)
        {[field_atom | select_acc], load_acc, updated_template}

      {:typed_struct_nested_selection, field_atom, nested_field_specs} ->
        # Handle TypedStruct nested field selection - generate nested typed struct instruction
        output_field = format_output_field_name(field_atom, context.formatter)
        instruction = ExtractionTemplate.typed_struct_nested_selection_field(field_atom, nested_field_specs)
        updated_template = ExtractionTemplate.put_instruction(template_acc, output_field, instruction)
        {[field_atom | select_acc], load_acc, updated_template}

      {:embedded_resource_selection, field_atom, field_spec} ->
        # Handle embedded resource with field selection - generate nested template
        output_field = format_output_field_name(field_atom, context.formatter)
        embedded_module = get_embedded_resource_module(field_atom, context.resource)
        nested_template = build_nested_extraction_template_for_resource(field_spec, embedded_module, context.formatter)
        instruction = ExtractionTemplate.nested_field(field_atom, nested_template)
        updated_template = ExtractionTemplate.put_instruction(template_acc, output_field, instruction)
        {[field_atom | select_acc], load_acc, updated_template}

      {:embedded_resource_with_load, field_atom, load_statement, field_spec} ->
        # Handle embedded resource with both select and load - generate nested template
        output_field = format_output_field_name(field_atom, context.formatter)
        embedded_module = get_embedded_resource_module(field_atom, context.resource)
        nested_template = build_nested_extraction_template_for_resource(field_spec, embedded_module, context.formatter)
        instruction = ExtractionTemplate.nested_field(field_atom, nested_template)
        updated_template = ExtractionTemplate.put_instruction(template_acc, output_field, instruction)
        {[field_atom | select_acc], [load_statement | load_acc], updated_template}

      {:skip, _field_atom} ->
        # Skip unknown fields gracefully
        {select_acc, load_acc, template_acc}
    end
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
  # Handle tuple input directly (from map entries)
  def process_field({field_name, field_spec}, %Context{} = context) do
    field_atom = FieldFormatter.parse_input_field(field_name, context.formatter)
    classify_and_process(field_atom, field_spec, context)
  end

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
            # No loadable items (calculations/relationships) - return embedded resource selection
            {:embedded_resource_selection, field_atom, field_spec}

          load_items ->
            # Both simple attributes (via select) and loadable items (via load) requested
            {:embedded_resource_with_load, field_atom, {field_atom, load_items}, field_spec}
        end

      :embedded_resource ->
        # Embedded resource without nested fields - SELECT the embedded attribute
        # Embedded resources are attributes that should be selected, not loaded
        {:select, field_atom}

      :typed_struct when is_list(field_spec) ->
        # TypedStruct with field selection (may include both simple fields and nested composite fields)
        # Check if all items are simple field names or if we have mixed content
        {simple_fields, nested_fields} =
          Enum.reduce(field_spec, {[], %{}}, fn item, {simple_acc, nested_acc} ->
            case item do
              field_name when is_binary(field_name) or is_atom(field_name) ->
                # Simple field name
                parsed_field =
                  AshTypescript.FieldFormatter.parse_input_field(field_name, context.formatter)

                {[parsed_field | simple_acc], nested_acc}

              %{} = nested_map when map_size(nested_map) == 1 ->
                # Single nested field specification (composite field)
                [{composite_field_name, composite_field_spec}] = Map.to_list(nested_map)

                parsed_composite_field =
                  AshTypescript.FieldFormatter.parse_input_field(
                    composite_field_name,
                    context.formatter
                  )

                parsed_composite_spec =
                  case composite_field_spec do
                    spec when is_list(spec) ->
                      Enum.map(spec, fn field_name ->
                        AshTypescript.FieldFormatter.parse_input_field(
                          field_name,
                          context.formatter
                        )
                      end)

                    _ ->
                      []
                  end

                updated_nested_acc =
                  Map.put(nested_acc, parsed_composite_field, parsed_composite_spec)

                {simple_acc, updated_nested_acc}

              _ ->
                # Unsupported format, skip
                {simple_acc, nested_acc}
            end
          end)

        # Decide how to handle based on what we found
        case {simple_fields, nested_fields} do
          {[], nested_specs} when map_size(nested_specs) > 0 ->
            # Only nested field specifications
            {:typed_struct_nested_selection, field_atom, nested_specs}

          {simple_specs, nested_specs} when map_size(nested_specs) > 0 ->
            # Mixed simple and nested - for now, combine into nested format
            # Include simple fields as "include all" and nested fields as specific selections
            combined_specs =
              Enum.reduce(simple_specs, nested_specs, fn simple_field, acc ->
                # For simple fields, we just include them without sub-field selection
                Map.put(acc, simple_field, [])
              end)

            {:typed_struct_nested_selection, field_atom, combined_specs}

          {simple_specs, _} ->
            # Only simple field specifications
            {:typed_struct_selection, field_atom, Enum.reverse(simple_specs)}
        end

      :typed_struct when is_map(field_spec) ->
        # TypedStruct with nested field selection for composite fields
        # Parse nested field specifications for composite type fields within the typed struct
        parsed_nested_field_specs =
          Enum.reduce(field_spec, %{}, fn {composite_field_name, composite_field_spec}, acc ->
            # Parse the composite field name from client format to internal format
            parsed_composite_field =
              AshTypescript.FieldFormatter.parse_input_field(
                composite_field_name,
                context.formatter
              )

            # Parse the field specifications for this composite field
            parsed_composite_spec =
              case composite_field_spec do
                spec when is_list(spec) ->
                  # List of field names for the composite field
                  Enum.map(spec, fn field_name ->
                    AshTypescript.FieldFormatter.parse_input_field(field_name, context.formatter)
                  end)

                _ ->
                  # Unsupported composite field spec format
                  []
              end

            Map.put(acc, parsed_composite_field, parsed_composite_spec)
          end)

        {:typed_struct_nested_selection, field_atom, parsed_nested_field_specs}

      :typed_struct ->
        # TypedStruct without field selection - SELECT the full TypedStruct attribute
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

      is_typed_struct_field?(field_name, resource) ->
        :typed_struct

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
        # Handle complex calculation with args within embedded resource
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
    {nested_select, nested_load, _nested_extraction_template} =
      parse_requested_fields(nested_fields, target_resource, formatter)

    # For relationships, combine select and load into a single nested load list
    combined_nested = nested_select ++ nested_load

    {relationship_name, combined_nested}
  end

  @doc """
  Builds an extraction template for nested fields (relationships, embedded resources).
  """
  def build_nested_extraction_template_for_resource(nested_fields, target_resource, formatter) do
    # Recursively process nested fields to generate extraction template
    {_nested_select, _nested_load, nested_extraction_template} =
      parse_requested_fields(nested_fields, target_resource, formatter)

    nested_extraction_template
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

  @doc "Check if a field is a TypedStruct attribute."
  def is_typed_struct_field?(field_name, resource) when is_atom(field_name) do
    case Ash.Resource.Info.attribute(resource, field_name) do
      nil -> false
      attribute -> is_typed_struct_type?(attribute.type)
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

  defp is_typed_struct_type?(module) when is_atom(module) do
    try do
      # Use the same detection logic as in the main codebase
      AshTypescript.Codegen.is_typed_struct?(module)
    rescue
      _ -> false
    end
  end

  defp is_typed_struct_type?({:array, module}) when is_atom(module) do
    is_typed_struct_type?(module)
  end

  defp is_typed_struct_type?(_), do: false

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

  # Helper functions for extraction template generation

  @doc """
  Formats a field atom using the output formatter for client consumption.
  """
  defp format_output_field_name(field_atom, formatter) when is_atom(field_atom) do
    field_string = Atom.to_string(field_atom)
    FieldFormatter.format_field(field_string, formatter)
  end

  @doc """
  Extracts the field atom from a load statement.
  """
  defp extract_field_atom_from_load_statement(load_statement) do
    case load_statement do
      {field_atom, _} when is_atom(field_atom) -> field_atom
      field_atom when is_atom(field_atom) -> field_atom
      _ -> :unknown_field
    end
  end

  @doc """
  Builds a nested extraction template for calculation results that need field filtering.
  """
  defp build_nested_extraction_template({simple_fields, _nested_specs}, context) when is_list(simple_fields) do
    # field_specs is a tuple {simple_fields, nested_specs} from LoadBuilder
    # Convert simple_fields to an extraction template
    Enum.reduce(simple_fields, ExtractionTemplate.new(), fn field, template_acc ->
      # Convert string field names to atoms if needed
      field_atom = case field do
        field when is_atom(field) -> field
        field when is_binary(field) -> FieldFormatter.parse_input_field(field, context.formatter)
        _ -> field
      end
      
      output_field = format_output_field_name(field_atom, context.formatter)
      instruction = ExtractionTemplate.extract_field(field_atom)
      ExtractionTemplate.put_instruction(template_acc, output_field, instruction)
    end)
  end

  defp build_nested_extraction_template(field_specs, context) when is_list(field_specs) do
    # field_specs is a list of fields that should be included in the calculation result
    # Convert it to an extraction template
    Enum.reduce(field_specs, ExtractionTemplate.new(), fn field_atom, template_acc ->
      output_field = format_output_field_name(field_atom, context.formatter)
      instruction = ExtractionTemplate.extract_field(field_atom)
      ExtractionTemplate.put_instruction(template_acc, output_field, instruction)
    end)
  end

  defp build_nested_extraction_template(field_specs, _context) do
    # Handle other field_specs formats - for now return empty template
    ExtractionTemplate.new()
  end

  @doc """
  Gets the nested field specification for a field from the current processing context.
  This is a simplified version that returns nil - in a real implementation,
  we would need to track the original field specification.
  """
  defp get_nested_field_spec_for_field(_field_atom, _context) do
    # TODO: This should return the original nested field specification
    # For now, return nil to avoid breaking the implementation
    nil
  end

  @doc """
  Determines the target resource for a field (relationship or embedded resource).
  """
  defp determine_target_resource_for_field(field_atom, resource) do
    cond do
      # Check if it's a relationship
      relationship = Ash.Resource.Info.relationship(resource, field_atom) ->
        relationship.destination

      # Check if it's an embedded resource attribute
      attribute = Ash.Resource.Info.attribute(resource, field_atom) ->
        case attribute.type do
          type when is_atom(type) ->
            if Ash.Resource.Info.embedded?(type), do: type, else: resource

          {:array, type} when is_atom(type) ->
            if Ash.Resource.Info.embedded?(type), do: type, else: resource

          _ ->
            resource
        end

      true ->
        # Fallback to same resource
        resource
    end
  end
end
