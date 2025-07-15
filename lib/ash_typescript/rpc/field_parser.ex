defmodule AshTypescript.Rpc.FieldParser do
  @moduledoc """
  Tree-based field parsing for building Ash load statements.
  
  Handles all field types including simple attributes, relationships,
  calculations, and embedded resources with a unified recursive approach.
  
  This module implements the new tree traversal architecture for field processing
  as described in the design document. It replaces the scattered field processing
  logic with a centralized, recursive approach.
  """

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
  @spec parse_requested_fields(fields :: list(), resource :: module(), formatter :: term()) ::
    {select_fields :: list(), load_statements :: list(), calculation_specs :: map()}
  def parse_requested_fields(fields, resource, formatter) do
    {select_fields, load_statements, calculation_specs} = 
      Enum.reduce(fields, {[], [], %{}}, fn field, {select_acc, load_acc, calc_specs_acc} ->
        case process_field_node(field, resource, formatter) do
          {:select, field_atom} -> 
            {[field_atom | select_acc], load_acc, calc_specs_acc}
          {:load, load_statement} -> 
            {select_acc, [load_statement | load_acc], calc_specs_acc}
          {:both, field_atom, load_statement} ->
            {[field_atom | select_acc], [load_statement | load_acc], calc_specs_acc}
          {:calculation_load, load_entry, field_specs} ->
            # NEW: Handle complex calculations with field specifications
            updated_calc_specs = if field_specs do
              # Extract calculation name from load entry
              calc_name = case load_entry do
                {name, _} -> name
                name -> name
              end
              Map.put(calc_specs_acc, calc_name, field_specs)
            else
              calc_specs_acc
            end
            {select_acc, [load_entry | load_acc], updated_calc_specs}
          {:skip, _field_atom} ->
            # Skip unknown fields gracefully
            {select_acc, load_acc, calc_specs_acc}
        end
      end)
    
    {Enum.reverse(select_fields), Enum.reverse(load_statements), calculation_specs}
  end

  @doc """
  Process a single field node in the tree traversal.
  
  Returns one of:
  - {:select, field_atom} - Field should go to select list
  - {:load, load_statement} - Field should go to load list  
  - {:both, field_atom, load_statement} - Field needs both select and load
  """
  def process_field_node(field, resource, formatter) when is_binary(field) do
    # Convert string field name to atom using formatter
    field_atom = AshTypescript.FieldFormatter.parse_input_field(field, formatter)
    
    case classify_field(field_atom, resource) do
      :simple_attribute ->
        {:select, field_atom}
        
      :simple_calculation ->
        {:load, field_atom}
        
      :complex_calculation ->
        # Complex calculation without arguments - load as simple calculation
        {:load, field_atom}
        
      :aggregate ->
        {:load, field_atom}
        
      :relationship ->
        # Relationship without nested fields - load the relationship itself
        {:load, field_atom}
        
      :embedded_resource ->
        # Embedded resource without nested fields - SELECT the embedded attribute
        # Embedded resources are attributes that should be selected, not loaded
        {:select, field_atom}
        
      :unknown ->
        # Unknown field - skip it to avoid Ash errors
        # Return a special tuple that can be filtered out later
        {:skip, field_atom}
    end
  end

  def process_field_node(field_map, resource, formatter) when is_map(field_map) do
    # Complex field specification: %{"field_name" => nested_fields_or_calc_spec}
    case Map.to_list(field_map) do
      [{field_name, field_spec}] ->
        field_atom = AshTypescript.FieldFormatter.parse_input_field(field_name, formatter)
        
        case classify_field(field_atom, resource) do
          :complex_calculation ->
            # NEW: Handle complex calculation with arguments
            process_complex_calculation(field_atom, field_spec, resource, formatter)
            
          :relationship when is_list(field_spec) ->
            target_resource = get_relationship_target_resource(field_atom, resource)
            nested_load = process_relationship_fields(field_atom, target_resource, field_spec, formatter)
            {:load, nested_load}
            
          :embedded_resource when is_list(field_spec) ->
            # For embedded resources with nested field selection:
            # 1. Always SELECT the embedded attribute (for simple attributes)
            # 2. Parse nested fields to detect loadable items (calculations, relationships)
            embedded_module = get_embedded_resource_module(field_atom, resource)
            embedded_load_items = process_embedded_fields(embedded_module, field_spec, formatter)
            
            case embedded_load_items do
              [] ->
                # No loadable items (calculations/relationships) - just select the embedded resource
                {:select, field_atom}
              load_items ->
                # Both simple attributes (via select) and loadable items (via load) requested
                {:both, field_atom, {field_atom, load_items}}
            end
            
          :unknown ->
            # Unknown field - skip it gracefully
            {:skip, field_atom}
            
          _ ->
            # Not a complex calculation, relationship, or embedded resource - treat as simple field
            {:load, field_atom}
        end
        
      _ ->
        # Invalid field specification
        {:load, field_map}  # Pass through as-is for now
    end
  end

  def process_field_node(field, _resource, _formatter) do
    # Unknown field format - pass through as load
    {:load, field}
  end

  @doc """
  Process a complex calculation with arguments and field selection.
  
  Complex calculations can have:
  - calcArgs: Arguments to pass to the calculation
  - fields: Fields to select from the calculation result  
  - calculations: Nested calculations if the result is a resource
  
  Returns {:calculation_load, load_entry, field_specs} where:
  - load_entry: Ash-compatible load statement
  - field_specs: Specification for result processing
  """
  def process_complex_calculation(calc_atom, calc_spec, resource, formatter) when is_map(calc_spec) do
    # Use output field formatter to get the expected client field name for calc_args
    calc_args_field = AshTypescript.FieldFormatter.format_field(:calc_args, AshTypescript.Rpc.output_field_formatter())
    
    # Extract calc_args, fields, and nested calculations from spec
    raw_calc_args = Map.get(calc_spec, calc_args_field, %{})
    
    # Parse calc_args using input field formatter - both the field name and individual arg names
    calc_args = AshTypescript.FieldFormatter.parse_input_fields(raw_calc_args, formatter)
                |> atomize_calc_args()
    
    fields = Map.get(calc_spec, "fields", [])
    nested_calcs = Map.get(calc_spec, "calculations", %{})
    
    # Build Ash load entry similar to current logic in rpc.ex
    load_entry = build_calculation_load_entry(calc_atom, calc_args, fields, nested_calcs, resource, formatter)
    
    # Build field specs for result processing
    field_specs = build_calculation_field_specs(calc_args, fields, nested_calcs)
    
    # Return with new calculation_load type
    {:calculation_load, load_entry, field_specs}
  end

  def process_complex_calculation(calc_atom, field_spec, _resource, _formatter) when is_list(field_spec) do
    # Complex calculation with just field selection (no arguments)
    # This is likely a relationship or embedded resource being processed as a calculation
    # Fall back to simple load for now
    {:load, {calc_atom, field_spec}}
  end

  def process_complex_calculation(calc_atom, _field_spec, _resource, _formatter) do
    # Invalid calculation specification - fall back to simple load
    {:load, calc_atom}
  end

  @doc """
  Classify a field by its type within a resource.
  
  Returns one of: :simple_attribute, :simple_calculation, :complex_calculation, :aggregate, 
  :relationship, :embedded_resource, :unknown
  """
  def classify_field(field_name, resource) when is_atom(field_name) do
    cond do
      is_embedded_resource_field?(field_name, resource) ->
        :embedded_resource
        
      is_relationship?(field_name, resource) ->
        :relationship
        
      is_calculation?(field_name, resource) ->
        # NEW: Distinguish between simple and complex calculations
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
  Check if a field is a simple attribute of the resource.
  """
  def is_simple_attribute?(field_name, resource) when is_atom(field_name) do
    resource
    |> Ash.Resource.Info.public_attributes()
    |> Enum.any?(&(&1.name == field_name))
  end

  @doc """
  Check if a field is a relationship of the resource.
  """
  def is_relationship?(field_name, resource) when is_atom(field_name) do
    resource
    |> Ash.Resource.Info.public_relationships()
    |> Enum.any?(&(&1.name == field_name))
  end

  @doc """
  Check if a field is an embedded resource attribute.
  """
  def is_embedded_resource_field?(field_name, resource) when is_atom(field_name) do
    case Ash.Resource.Info.attribute(resource, field_name) do
      nil -> 
        false
      attribute -> 
        is_embedded_resource_type?(attribute.type)
    end
  end

  @doc """
  Check if a field is a calculation of the resource.
  """
  def is_calculation?(field_name, resource) when is_atom(field_name) do
    resource
    |> Ash.Resource.Info.calculations()
    |> Enum.any?(&(&1.name == field_name))
  end

  @doc """
  Check if a field is an aggregate of the resource.
  """
  def is_aggregate?(field_name, resource) when is_atom(field_name) do
    resource
    |> Ash.Resource.Info.aggregates()
    |> Enum.any?(&(&1.name == field_name))
  end

  @doc """
  Get the calculation definition for a field.
  """
  def get_calculation_definition(field_name, resource) when is_atom(field_name) do
    resource
    |> Ash.Resource.Info.calculations()
    |> Enum.find(&(&1.name == field_name))
  end

  @doc """
  Check if a calculation definition has arguments.
  """
  def has_arguments?(calc_definition) do
    calc_definition && length(calc_definition.arguments) > 0
  end

  @doc """
  Process nested fields for embedded resources.
  
  For embedded resources:
  - Simple attributes are automatically loaded when the embedded resource is selected
  - Only calculations and relationships need to be explicitly loaded
  - Field selection happens during result processing
  
  Returns a list of load statements for calculations and relationships only.
  """
  def process_embedded_fields(embedded_module, nested_fields, formatter) do
    # Process each nested field and collect only loadable items
    Enum.reduce(nested_fields, [], fn field, acc ->
      case field do
        field_name when is_binary(field_name) ->
          field_atom = AshTypescript.FieldFormatter.parse_input_field(field_name, formatter)
          
          case classify_field(field_atom, embedded_module) do
            :simple_calculation ->
              # Calculation - needs to be loaded
              [field_atom | acc]
            :aggregate ->
              # Aggregate - needs to be loaded
              [field_atom | acc]
            :relationship ->
              # Relationship - needs to be loaded (simple load, no nested fields)
              [field_atom | acc]
            :simple_attribute ->
              # Simple attribute - automatically included, skip
              acc
            :embedded_resource ->
              # Nested embedded resource - treat as simple load for now
              [field_atom | acc]
            :unknown ->
              # Unknown field - skip for safety
              acc
          end
          
        field_map when is_map(field_map) ->
          # Complex nested field (relationship, embedded resource, or complex calculation with sub-selections)
          case Map.to_list(field_map) do
            [{field_name, nested_fields_inner}] when is_binary(field_name) and is_list(nested_fields_inner) ->
              field_atom = AshTypescript.FieldFormatter.parse_input_field(field_name, formatter)
              
              case classify_field(field_atom, embedded_module) do
                :relationship ->
                  # Relationship with nested fields
                  target_resource = get_relationship_target_resource(field_atom, embedded_module)
                  nested_load = process_relationship_fields(field_atom, target_resource, nested_fields_inner, formatter)
                  [nested_load | acc]
                  
                :embedded_resource ->
                  # Nested embedded resource with nested fields
                  nested_embedded_module = get_embedded_resource_module(field_atom, embedded_module)
                  nested_load_items = process_embedded_fields(nested_embedded_module, nested_fields_inner, formatter)
                  
                  case nested_load_items do
                    [] ->
                      # No loadable items in nested embedded resource - skip
                      acc
                    items ->
                      # Has loadable items - include in load
                      [{field_atom, items} | acc]
                  end
                  
                _ ->
                  # Not a loadable complex field - skip
                  acc
              end
              
            [{field_name, calc_spec}] when is_binary(field_name) and is_map(calc_spec) ->
              # NEW: Handle complex calculation with calcArgs within embedded resource
              field_atom = AshTypescript.FieldFormatter.parse_input_field(field_name, formatter)
              
              case classify_field(field_atom, embedded_module) do
                :complex_calculation ->
                  # Complex calculation with arguments - use same logic as main field parser
                  calc_load_entry = build_embedded_calculation_load_entry(field_atom, calc_spec, embedded_module, formatter)
                  [calc_load_entry | acc]
                  
                :unknown ->
                  # Unknown field - skip it gracefully
                  acc
                  
                _ ->
                  # Not a complex calculation - skip
                  acc
              end
              
            _ ->
              # Invalid field map format - skip
              acc
          end
          
        _ ->
          # Unknown field format - skip
          acc
      end
    end)
    |> Enum.reverse()
  end

  @doc """
  Process nested fields for relationships.
  
  Returns a load statement in the format {:relationship_name, nested_loads}.
  """
  def process_relationship_fields(relationship_name, target_resource, nested_fields, formatter) do
    # Recursively process nested fields using the relationship target resource
    {nested_select, nested_load, _nested_calc_specs} = parse_requested_fields(nested_fields, target_resource, formatter)
    
    # For relationships, combine select and load into a single nested load list
    combined_nested = nested_select ++ nested_load
    
    {relationship_name, combined_nested}
  end

  @doc """
  Build a load statement based on field type.
  """
  def build_load_statement(:simple_calculation, field_name, _nested_data, _resource) do
    field_name
  end

  def build_load_statement(:relationship, field_name, nested_fields, _resource) when is_list(nested_fields) do
    {field_name, nested_fields}
  end

  def build_load_statement(:embedded_resource, field_name, nested_fields, _resource) when is_list(nested_fields) do
    {field_name, nested_fields}
  end

  def build_load_statement(_, field_name, _nested_data, _resource) do
    field_name
  end

  # Helper functions for complex calculation processing

  @doc """
  Atomize calculation arguments from string keys to atom keys.
  """
  def atomize_calc_args(args) when is_map(args) do
    Enum.reduce(args, %{}, fn {k, v}, acc ->
      atom_key = if is_binary(k), do: String.to_existing_atom(k), else: k
      Map.put(acc, atom_key, v)
    end)
  end

  @doc """
  Build Ash-compatible load entry for complex calculations.
  """
  def build_calculation_load_entry(calc_atom, calc_args, fields, nested_calcs, resource, formatter) do
    # Parse fields and build nested load
    parsed_fields = parse_field_names_for_load(fields, formatter)
    
    # Handle nested calculations if any
    nested_load = if map_size(nested_calcs) > 0 do
      calc_definition = get_calculation_definition(calc_atom, resource)
      if is_resource_calculation?(calc_definition) do
        target_resource = get_calculation_return_resource(calc_definition)
        parse_nested_calculations(nested_calcs, target_resource, formatter)
      else
        []
      end
    else
      []
    end
    
    # Combine fields and nested calculations
    combined_load = parsed_fields ++ nested_load
    
    # Build load entry in Ash format
    case {map_size(calc_args), length(combined_load)} do
      {0, 0} -> calc_atom
      {0, _} -> {calc_atom, combined_load}
      {_, 0} -> {calc_atom, calc_args}
      {_, _} -> {calc_atom, {calc_args, combined_load}}
    end
  end

  @doc """
  Build field specifications for result processing.
  """
  def build_calculation_field_specs(calc_args, fields, nested_specs) do
    # Only need field specs if we have arguments AND (fields or nested calculations)
    if map_size(calc_args) > 0 and (length(fields) > 0 or map_size(nested_specs) > 0) do
      # Extract nested calculation specs from the fields list
      {simple_fields, extracted_nested_specs} = extract_nested_calc_specs_from_fields(fields)
      
      # Combine any existing nested specs with extracted ones
      combined_nested_specs = Map.merge(nested_specs, extracted_nested_specs)
      
      {simple_fields, combined_nested_specs}
    else
      nil
    end
  end

  @doc """
  Extract nested calculation specs from fields list.
  
  Separates simple fields from nested calculation maps and returns
  both the simple fields and the extracted nested calculation specs.
  """
  def extract_nested_calc_specs_from_fields(fields) do
    Enum.reduce(fields, {[], %{}}, fn field, {simple_fields_acc, nested_specs_acc} ->
      case field do
        %{} = field_map when map_size(field_map) == 1 ->
          # This is a nested calculation
          [{calc_name, calc_spec}] = Map.to_list(field_map)
          
          case calc_spec do
            %{"calcArgs" => _calc_args, "fields" => calc_fields} ->
              # Extract nested specs from calc_fields recursively
              {simple_calc_fields, deeper_nested_specs} = extract_nested_calc_specs_from_fields(calc_fields)
              
              # Store the spec for this calculation
              calc_atom = String.to_atom(calc_name)
              nested_spec = {simple_calc_fields, deeper_nested_specs}
              
              {simple_fields_acc, Map.put(nested_specs_acc, calc_atom, nested_spec)}
            _ ->
              # Not a valid nested calculation, treat as simple field
              {[field | simple_fields_acc], nested_specs_acc}
          end
        _ ->
          # Simple field
          {[field | simple_fields_acc], nested_specs_acc}
      end
    end)
  end

  @doc """
  Build Ash-compatible load entry for complex calculations within embedded resources.
  
  This is similar to build_calculation_load_entry but specifically for embedded resource calculations.
  """
  def build_embedded_calculation_load_entry(calc_atom, calc_spec, embedded_module, formatter) do
    # Use output field formatter to get the expected client field name for calc_args
    calc_args_field = AshTypescript.FieldFormatter.format_field(:calc_args, AshTypescript.Rpc.output_field_formatter())
    
    # Extract calc_args from spec
    raw_calc_args = Map.get(calc_spec, calc_args_field, %{})
    
    # Parse calc_args using input field formatter
    calc_args = AshTypescript.FieldFormatter.parse_input_fields(raw_calc_args, formatter)
                |> atomize_calc_args()
    
    # For embedded resource calculations, we typically don't have nested fields/calculations
    # But we should check if they exist
    fields = Map.get(calc_spec, "fields", [])
    nested_calcs = Map.get(calc_spec, "calculations", %{})
    
    # Parse fields for load format
    parsed_fields = parse_field_names_for_load(fields, formatter)
    
    # Handle nested calculations if any (similar to main calculation logic)
    nested_load = if map_size(nested_calcs) > 0 do
      calc_definition = get_calculation_definition(calc_atom, embedded_module)
      if is_resource_calculation?(calc_definition) do
        target_resource = get_calculation_return_resource(calc_definition)
        parse_nested_calculations(nested_calcs, target_resource, formatter)
      else
        []
      end
    else
      []
    end
    
    # Combine fields and nested calculations
    combined_load = parsed_fields ++ nested_load
    
    # Build load entry in Ash format (same logic as main calculations)
    case {map_size(calc_args), length(combined_load)} do
      {0, 0} -> calc_atom
      {0, _} -> {calc_atom, combined_load}
      {_, 0} -> {calc_atom, calc_args}
      {_, _} -> {calc_atom, {calc_args, combined_load}}
    end
  end

  @doc """
  Parse field names for load format.
  """
  def parse_field_names_for_load(fields, formatter) when is_list(fields) do
    fields
    |> Enum.map(fn field ->
      case field do
        field when is_binary(field) ->
          AshTypescript.FieldFormatter.parse_input_field(field, formatter)
        field_map when is_map(field_map) ->
          # Process nested field maps recursively
          # We need to extract the load statement from the field processing
          # Since this is within a calculation's field list, we need to handle maps specially
          case Map.to_list(field_map) do
            [{field_name, field_spec}] ->
              field_atom = AshTypescript.FieldFormatter.parse_input_field(field_name, formatter)
              case field_spec do
                %{"calcArgs" => calc_args, "fields" => nested_fields} ->
                  # This is a nested calculation
                  parsed_args = AshTypescript.FieldFormatter.parse_input_fields(calc_args, formatter)
                                |> atomize_calc_args()
                  parsed_nested_fields = parse_field_names_for_load(nested_fields, formatter)
                  
                  # Build the load entry
                  case {map_size(parsed_args), length(parsed_nested_fields)} do
                    {0, 0} -> field_atom
                    {0, _} -> {field_atom, parsed_nested_fields}
                    {_, 0} -> {field_atom, parsed_args}
                    {_, _} -> {field_atom, {parsed_args, parsed_nested_fields}}
                  end
                _ ->
                  # Other nested structure - just use the field name
                  field_atom
              end
            _ ->
              # Invalid map structure - skip it
              nil
          end
        field ->
          field
      end
    end)
    |> Enum.filter(fn x -> x != nil end)
  end

  @doc """
  Parse nested calculations recursively.
  """
  def parse_nested_calculations(nested_calcs, _target_resource, _formatter) when is_map(nested_calcs) do
    # This is a simplified version - full recursive processing would be implemented later
    # For now, just return empty list
    []
  end

  @doc """
  Check if calculation returns an Ash resource.
  """
  def is_resource_calculation?(calc_definition) when is_nil(calc_definition), do: false
  def is_resource_calculation?(calc_definition) do
    case calc_definition.type do
      Ash.Type.Struct ->
        # Check if constraints specify instance_of an Ash resource
        case Keyword.get(calc_definition.constraints || [], :instance_of) do
          module when is_atom(module) -> Ash.Resource.Info.resource?(module)
          _ -> false
        end
      _ -> false
    end
  end

  @doc """
  Get the resource that a calculation returns.
  """
  def get_calculation_return_resource(calc_definition) when is_nil(calc_definition), do: nil
  def get_calculation_return_resource(calc_definition) do
    case calc_definition.type do
      Ash.Type.Struct ->
        # Check if constraints specify instance_of an Ash resource
        case Keyword.get(calc_definition.constraints || [], :instance_of) do
          module when is_atom(module) ->
            if Ash.Resource.Info.resource?(module) do
              module
            else
              nil
            end
          _ -> nil
        end
      _ -> nil
    end
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

  defp get_relationship_target_resource(relationship_name, resource) do
    resource
    |> Ash.Resource.Info.public_relationships()
    |> Enum.find(&(&1.name == relationship_name))
    |> case do
      nil -> resource  # Fallback to same resource
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
            loadable_only = Enum.filter(nested_fields, fn 
              nested_field when is_atom(nested_field) ->
                is_calculation?(nested_field, embedded_module) or is_aggregate?(nested_field, embedded_module)
              _ ->
                true  # Keep complex nested structures as-is
            end)
            
            # 🔧 KEY FIX: If no loadable items remain, return :skip to exclude from Ash load
            # Embedded attributes are automatically loaded by Ash, so empty loadable
            # lists should not be sent to Ash.Query.load/2
            case loadable_only do
              [] -> :skip  # Will be filtered out in next step
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
    |> Enum.reject(&(&1 == :skip))  # Remove skipped embedded resources with no calculations
  end
end