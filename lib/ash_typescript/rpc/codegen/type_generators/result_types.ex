# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen.TypeGenerators.ResultTypes do
  @moduledoc """
  Generates TypeScript result types for RPC actions.

  Result types define the shape of data returned from RPC actions, including:
  - Field selection types (which fields can be selected)
  - Inferred result types (what the result looks like given a field selection)
  - Pagination wrapper types (for paginated results)
  - Metadata integration (for actions that return metadata)
  """

  import AshTypescript.Codegen
  import AshTypescript.Helpers

  alias AshTypescript.Rpc.Codegen.Helpers.ActionIntrospection
  alias AshTypescript.Rpc.Codegen.TypeGenerators.MetadataTypes
  alias AshTypescript.Rpc.Codegen.TypeGenerators.PaginationTypes
  alias AshTypescript.Rpc.Codegen.TypeGenerators.RestrictedSchema

  @doc """
  Generates the TypeScript result type for an RPC action.

  The generated type includes:
  - A Fields type (what fields can be selected)
  - An InferResult type (what the result will be given a field selection)
  - Optional metadata types (if metadata is enabled)
  - Optional pagination types (if the action supports pagination)

  ## Parameters

    * `resource` - The Ash resource
    * `action` - The Ash action
    * `rpc_action` - The RPC action configuration
    * `rpc_action_name` - The snake_case name of the RPC action

  ## Returns

  A string containing the TypeScript type definitions for this action's result.
  """
  def generate_result_type(resource, action, rpc_action, rpc_action_name) do
    rpc_action_name_pascal = snake_to_pascal_case(rpc_action_name)

    # Get restricted schema if load restrictions are configured
    {schema_def, schema_ref} =
      RestrictedSchema.get_schema_and_reference(resource, rpc_action, rpc_action_name_pascal)

    # Check both Ash's native get? and RPC's get?/get_by options
    ash_get? = action.type == :read and Map.get(action, :get?, false)
    rpc_get? = Map.get(rpc_action, :get?, false)
    rpc_get_by = (Map.get(rpc_action, :get_by) || []) != []

    is_get_action = ash_get? or rpc_get? or rpc_get_by

    # When not_found_error? is true (default), don't add | null (errors are returned instead)
    # If not explicitly set (nil), use the global config default
    not_found_error? =
      case Map.get(rpc_action, :not_found_error?) do
        nil -> AshTypescript.Rpc.not_found_error?()
        value -> value
      end

    null_suffix = if not_found_error?, do: "", else: " | null"

    # Helper to prepend schema definition if it exists
    prepend_schema_def = fn result ->
      if schema_def do
        schema_def <> "\n" <> result
      else
        result
      end
    end

    case {action.type, is_get_action} do
      {:read, true} ->
        metadata_type =
          MetadataTypes.generate_action_metadata_type(action, rpc_action, rpc_action_name_pascal)

        has_metadata =
          MetadataTypes.metadata_enabled?(
            MetadataTypes.get_exposed_metadata_fields(rpc_action, action)
          )

        result =
          if has_metadata do
            """
            export type #{rpc_action_name_pascal}Fields = UnifiedFieldSelection<#{schema_ref}>[];
            #{metadata_type}
            export type Infer#{rpc_action_name_pascal}Result<
              Fields extends #{rpc_action_name_pascal}Fields,
              MetadataFields extends ReadonlyArray<keyof #{rpc_action_name_pascal}Metadata> = []
            > = (InferResult<#{schema_ref}, Fields> & Pick<#{rpc_action_name_pascal}Metadata, MetadataFields[number]>)#{null_suffix};
            """
          else
            """
            export type #{rpc_action_name_pascal}Fields = UnifiedFieldSelection<#{schema_ref}>[];
            export type Infer#{rpc_action_name_pascal}Result<
              Fields extends #{rpc_action_name_pascal}Fields,
            > = InferResult<#{schema_ref}, Fields>#{null_suffix};
            """
          end

        prepend_schema_def.(result)

      {:read, false} ->
        result =
          if ActionIntrospection.action_supports_pagination?(action) do
            metadata_type =
              MetadataTypes.generate_action_metadata_type(
                action,
                rpc_action,
                rpc_action_name_pascal
              )

            has_metadata =
              MetadataTypes.metadata_enabled?(
                MetadataTypes.get_exposed_metadata_fields(rpc_action, action)
              )

            fields_type = """
            export type #{rpc_action_name_pascal}Fields = UnifiedFieldSelection<#{schema_ref}>[];
            #{metadata_type}
            """

            pagination_type =
              if ActionIntrospection.action_requires_pagination?(action) do
                PaginationTypes.generate_pagination_result_type(
                  resource,
                  action,
                  rpc_action_name_pascal,
                  schema_ref,
                  has_metadata
                )
              else
                PaginationTypes.generate_conditional_pagination_result_type(
                  resource,
                  action,
                  rpc_action_name_pascal,
                  schema_ref,
                  has_metadata
                )
              end

            fields_type <> "\n" <> pagination_type
          else
            metadata_type =
              MetadataTypes.generate_action_metadata_type(
                action,
                rpc_action,
                rpc_action_name_pascal
              )

            has_metadata =
              MetadataTypes.metadata_enabled?(
                MetadataTypes.get_exposed_metadata_fields(rpc_action, action)
              )

            if has_metadata do
              """
              export type #{rpc_action_name_pascal}Fields = UnifiedFieldSelection<#{schema_ref}>[];
              #{metadata_type}
              export type Infer#{rpc_action_name_pascal}Result<
                Fields extends #{rpc_action_name_pascal}Fields,
                MetadataFields extends ReadonlyArray<keyof #{rpc_action_name_pascal}Metadata> = []
              > = Array<InferResult<#{schema_ref}, Fields> & Pick<#{rpc_action_name_pascal}Metadata, MetadataFields[number]>>;
              """
            else
              """
              export type #{rpc_action_name_pascal}Fields = UnifiedFieldSelection<#{schema_ref}>[];
              export type Infer#{rpc_action_name_pascal}Result<
                Fields extends #{rpc_action_name_pascal}Fields,
              > = Array<InferResult<#{schema_ref}, Fields>>;
              """
            end
          end

        prepend_schema_def.(result)

      {action_type, _} when action_type in [:create, :update] ->
        metadata_type =
          MetadataTypes.generate_action_metadata_type(action, rpc_action, rpc_action_name_pascal)

        has_metadata =
          MetadataTypes.metadata_enabled?(
            MetadataTypes.get_exposed_metadata_fields(rpc_action, action)
          )

        result =
          if has_metadata do
            """
            export type #{rpc_action_name_pascal}Fields = UnifiedFieldSelection<#{schema_ref}>[];
            #{metadata_type}
            export type Infer#{rpc_action_name_pascal}Result<
              Fields extends #{rpc_action_name_pascal}Fields | undefined,
              MetadataFields extends ReadonlyArray<keyof #{rpc_action_name_pascal}Metadata> = []
            > = InferResult<#{schema_ref}, Fields>;
            """
          else
            """
            export type #{rpc_action_name_pascal}Fields = UnifiedFieldSelection<#{schema_ref}>[];
            #{metadata_type}
            export type Infer#{rpc_action_name_pascal}Result<
              Fields extends #{rpc_action_name_pascal}Fields | undefined,
            > = InferResult<#{schema_ref}, Fields>;
            """
          end

        prepend_schema_def.(result)

      {:destroy, _} ->
        metadata_type =
          MetadataTypes.generate_action_metadata_type(action, rpc_action, rpc_action_name_pascal)

        has_metadata =
          MetadataTypes.metadata_enabled?(
            MetadataTypes.get_exposed_metadata_fields(rpc_action, action)
          )

        if has_metadata do
          """
          #{metadata_type}
          export type Infer#{rpc_action_name_pascal}Result<
            MetadataFields extends ReadonlyArray<keyof #{rpc_action_name_pascal}Metadata> = []
          > = {};
          """
        else
          metadata_type
        end

      {:action, _} ->
        case ActionIntrospection.action_returns_field_selectable_type?(action) do
          {:ok, type, value} when type in [:resource, :array_of_resource] ->
            target_resource_name = build_resource_type_name(value)

            if type == :array_of_resource do
              """
              export type #{rpc_action_name_pascal}Fields = UnifiedFieldSelection<#{target_resource_name}ResourceSchema>[];

              export type Infer#{rpc_action_name_pascal}Result<
                Fields extends #{rpc_action_name_pascal}Fields | undefined,
              > = Array<InferResult<#{target_resource_name}ResourceSchema, Fields>>;
              """
            else
              """
              export type #{rpc_action_name_pascal}Fields = UnifiedFieldSelection<#{target_resource_name}ResourceSchema>[];

              export type Infer#{rpc_action_name_pascal}Result<
                Fields extends #{rpc_action_name_pascal}Fields | undefined,
              > = InferResult<#{target_resource_name}ResourceSchema, Fields>;
              """
            end

          {:ok, type, value} when type in [:typed_map, :array_of_typed_map] ->
            typed_map_schema = build_map_type(value)

            if type == :array_of_typed_map do
              """
              export type #{rpc_action_name_pascal}Fields = UnifiedFieldSelection<#{typed_map_schema}>[];

              export type Infer#{rpc_action_name_pascal}Result<
                Fields extends #{rpc_action_name_pascal}Fields | undefined,
              > = Array<InferResult<#{typed_map_schema}, Fields>>;
              """
            else
              """
              export type #{rpc_action_name_pascal}Fields = UnifiedFieldSelection<#{typed_map_schema}>[];

              export type Infer#{rpc_action_name_pascal}Result<
                Fields extends #{rpc_action_name_pascal}Fields | undefined,
              > = InferResult<#{typed_map_schema}, Fields>;
              """
            end

          {:ok, :typed_struct, {module, fields}} ->
            field_name_mappings =
              if function_exported?(module, :typescript_field_names, 0) do
                module.typescript_field_names()
              else
                nil
              end

            typed_map_schema = build_map_type(fields, nil, field_name_mappings)

            """
            export type #{rpc_action_name_pascal}Fields = UnifiedFieldSelection<#{typed_map_schema}>[];

            export type Infer#{rpc_action_name_pascal}Result<
              Fields extends #{rpc_action_name_pascal}Fields | undefined,
            > = InferResult<#{typed_map_schema}, Fields>;
            """

          {:ok, :array_of_typed_struct, {module, fields}} ->
            field_name_mappings =
              if function_exported?(module, :typescript_field_names, 0) do
                module.typescript_field_names()
              else
                nil
              end

            typed_map_schema = build_map_type(fields, nil, field_name_mappings)

            """
            export type #{rpc_action_name_pascal}Fields = UnifiedFieldSelection<#{typed_map_schema}>[];

            export type Infer#{rpc_action_name_pascal}Result<
              Fields extends #{rpc_action_name_pascal}Fields | undefined,
            > = Array<InferResult<#{typed_map_schema}, Fields>>;
            """

          {:ok, :unconstrained_map, _} ->
            """
            export type Infer#{rpc_action_name_pascal}Result = Record<string, any>;
            """

          _ ->
            if action.returns do
              return_type = get_ts_type(%{type: action.returns, constraints: action.constraints})

              """
              export type Infer#{rpc_action_name_pascal}Result = #{return_type};
              """
            else
              """
              export type Infer#{rpc_action_name_pascal}Result = {};
              """
            end
        end
    end
  end
end
