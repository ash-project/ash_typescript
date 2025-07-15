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
  
  Takes a list of field specifications and returns a tuple of {select_fields, load_statements}
  where select_fields are simple attributes for Ash.Query.select/2 and load_statements
  are loadable fields for Ash.Query.load/2.
  
  ## Examples
  
      iex> fields = ["id", "title", "displayName", %{"user" => ["name"]}]
      iex> parse_requested_fields(fields, MyApp.Todo, :camel_case)
      {[:id, :title], [:display_name, {:user, [:name]}]}
      
      iex> fields = [%{"metadata" => ["category", "displayCategory"]}]
      iex> parse_requested_fields(fields, MyApp.Todo, :camel_case)
      {[], [{:metadata, [:display_category]}]}
  """
  @spec parse_requested_fields(fields :: list(), resource :: module(), formatter :: term()) ::
    {select_fields :: list(), load_statements :: list()}
  def parse_requested_fields(fields, resource, formatter) do
    {select_fields, load_statements} = 
      Enum.reduce(fields, {[], []}, fn field, {select_acc, load_acc} ->
        case process_field_node(field, resource, formatter) do
          {:select, field_atom} -> 
            {[field_atom | select_acc], load_acc}
          {:load, load_statement} -> 
            {select_acc, [load_statement | load_acc]}
          {:both, field_atom, load_statement} ->
            {[field_atom | select_acc], [load_statement | load_acc]}
        end
      end)
    
    {Enum.reverse(select_fields), Enum.reverse(load_statements)}
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
        
      :relationship ->
        # Relationship without nested fields - load the relationship itself
        {:load, field_atom}
        
      :embedded_resource ->
        # Embedded resource without nested fields - load the entire embedded object
        {:load, field_atom}
        
      :unknown ->
        # Unknown field - skip it (or could raise an error)
        {:select, field_atom}  # Default to select for now
    end
  end

  def process_field_node(field_map, resource, formatter) when is_map(field_map) do
    # Complex field specification: %{"field_name" => nested_fields}
    case Map.to_list(field_map) do
      [{field_name, nested_fields}] when is_list(nested_fields) ->
        field_atom = AshTypescript.FieldFormatter.parse_input_field(field_name, formatter)
        
        case classify_field(field_atom, resource) do
          :relationship ->
            target_resource = get_relationship_target_resource(field_atom, resource)
            nested_load = process_relationship_fields(field_atom, target_resource, nested_fields, formatter)
            {:load, nested_load}
            
          :embedded_resource ->
            embedded_module = get_embedded_resource_module(field_atom, resource)
            embedded_load = process_embedded_fields(embedded_module, nested_fields, formatter)
            {:load, {field_atom, embedded_load}}
            
          _ ->
            # Not a relationship or embedded resource - treat as simple field
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
  Classify a field by its type within a resource.
  
  Returns one of: :simple_attribute, :simple_calculation, :relationship, 
  :embedded_resource, :unknown
  """
  def classify_field(field_name, resource) when is_atom(field_name) do
    cond do
      is_embedded_resource_field?(field_name, resource) ->
        :embedded_resource
        
      is_relationship?(field_name, resource) ->
        :relationship
        
      is_calculation?(field_name, resource) ->
        :simple_calculation
        
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
  Process nested fields for embedded resources.
  
  Returns a list of load statements for the embedded resource.
  """
  def process_embedded_fields(embedded_module, nested_fields, formatter) do
    # Recursively process nested fields using the embedded resource as the new "root"
    {_embedded_select, embedded_load} = parse_requested_fields(nested_fields, embedded_module, formatter)
    
    # For embedded resources, we need to load calculations but select is handled differently
    # since embedded attributes are loaded as complete objects, then field selection is applied
    embedded_load
  end

  @doc """
  Process nested fields for relationships.
  
  Returns a load statement in the format {:relationship_name, nested_loads}.
  """
  def process_relationship_fields(relationship_name, target_resource, nested_fields, formatter) do
    # Recursively process nested fields using the relationship target resource
    {nested_select, nested_load} = parse_requested_fields(nested_fields, target_resource, formatter)
    
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
end