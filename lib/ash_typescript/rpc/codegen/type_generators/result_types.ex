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

  alias AshTypescript.Codegen.ClientNames
  alias AshTypescript.Rpc.Codegen.FunctionNames
  alias AshTypescript.Rpc.Codegen.Helpers.{ActionIntrospection, EntrypointOptions}
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
  def generate_result_type(resource, action, rpc_action, rpc_action_name, resource_lookup) do
    infer_result_type_name = FunctionNames.infer_result_type(rpc_action_name)
    fields_type_name = FunctionNames.fields_type(rpc_action_name)
    metadata_type_name = FunctionNames.metadata_type(rpc_action_name)

    # Get restricted schema if load restrictions are configured
    {schema_def, schema_ref} =
      RestrictedSchema.get_schema_and_reference(resource, rpc_action, resource_lookup)

    entrypoint = EntrypointOptions.entrypoint!(rpc_action)
    is_get_action = EntrypointOptions.get?(entrypoint, action)

    # When not_found_error? is true, a missing record is an error, not null
    null_suffix = if EntrypointOptions.not_found_error?(entrypoint), do: "", else: " | null"

    # Empty when the action exposes no metadata.
    metadata_type =
      MetadataTypes.generate_action_metadata_type(action, rpc_action, rpc_action_name)

    has_metadata =
      MetadataTypes.metadata_enabled?(MetadataTypes.exposed_metadata_fields(rpc_action))

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
        result =
          if has_metadata do
            """
            export type #{fields_type_name} = #{unified_field_selection_ref(schema_ref, rpc_action)}[];
            #{metadata_type}
            export type #{infer_result_type_name}<
              Fields extends #{fields_type_name},
              MetadataFields extends ReadonlyArray<keyof #{metadata_type_name}> = []
            > = (InferResult<#{schema_ref}, Fields> & Pick<#{metadata_type_name}, MetadataFields[number]>)#{null_suffix};
            """
          else
            """
            export type #{fields_type_name} = #{unified_field_selection_ref(schema_ref, rpc_action)}[];
            export type #{infer_result_type_name}<
              Fields extends #{fields_type_name},
            > = InferResult<#{schema_ref}, Fields>#{null_suffix};
            """
          end

        prepend_schema_def.(result)

      {:read, false} ->
        result =
          if ActionIntrospection.action_supports_pagination?(action) do
            fields_type = """
            export type #{fields_type_name} = #{unified_field_selection_ref(schema_ref, rpc_action)}[];
            #{metadata_type}
            """

            pagination_type =
              if ActionIntrospection.action_requires_pagination?(action) do
                PaginationTypes.generate_pagination_result_type(
                  resource,
                  action,
                  rpc_action_name,
                  schema_ref,
                  has_metadata
                )
              else
                PaginationTypes.generate_conditional_pagination_result_type(
                  resource,
                  action,
                  rpc_action_name,
                  schema_ref,
                  has_metadata
                )
              end

            fields_type <> "\n" <> pagination_type
          else
            if has_metadata do
              """
              export type #{fields_type_name} = #{unified_field_selection_ref(schema_ref, rpc_action)}[];
              #{metadata_type}
              export type #{infer_result_type_name}<
                Fields extends #{fields_type_name},
                MetadataFields extends ReadonlyArray<keyof #{metadata_type_name}> = []
              > = Array<InferResult<#{schema_ref}, Fields> & Pick<#{metadata_type_name}, MetadataFields[number]>>;
              """
            else
              """
              export type #{fields_type_name} = #{unified_field_selection_ref(schema_ref, rpc_action)}[];
              export type #{infer_result_type_name}<
                Fields extends #{fields_type_name},
              > = Array<InferResult<#{schema_ref}, Fields>>;
              """
            end
          end

        prepend_schema_def.(result)

      {action_type, _} when action_type in [:create, :update] ->
        result =
          if has_metadata do
            """
            export type #{fields_type_name} = #{unified_field_selection_ref(schema_ref, rpc_action)}[];
            #{metadata_type}
            export type #{infer_result_type_name}<
              Fields extends #{fields_type_name} | undefined,
              MetadataFields extends ReadonlyArray<keyof #{metadata_type_name}> = []
            > = InferResult<#{schema_ref}, Fields>;
            """
          else
            """
            export type #{fields_type_name} = #{unified_field_selection_ref(schema_ref, rpc_action)}[];
            #{metadata_type}
            export type #{infer_result_type_name}<
              Fields extends #{fields_type_name} | undefined,
            > = InferResult<#{schema_ref}, Fields>;
            """
          end

        prepend_schema_def.(result)

      {:destroy, _} ->
        if has_metadata do
          """
          #{metadata_type}
          export type #{infer_result_type_name}<
            MetadataFields extends ReadonlyArray<keyof #{metadata_type_name}> = []
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
              export type #{fields_type_name} = #{unified_field_selection_ref("#{target_resource_name}ResourceSchema", rpc_action)}[];

              export type #{infer_result_type_name}<
                Fields extends #{fields_type_name} | undefined,
              > = Array<InferResult<#{target_resource_name}ResourceSchema, Fields>>;
              """
            else
              """
              export type #{fields_type_name} = #{unified_field_selection_ref("#{target_resource_name}ResourceSchema", rpc_action)}[];

              export type #{infer_result_type_name}<
                Fields extends #{fields_type_name} | undefined,
              > = InferResult<#{target_resource_name}ResourceSchema, Fields>;
              """
            end

          {:ok, type, _fields} when type in [:typed_map, :array_of_typed_map] ->
            typed_map_schema = action.returns |> return_container() |> build_map_type()

            if type == :array_of_typed_map do
              """
              export type #{fields_type_name} = #{unified_field_selection_ref(typed_map_schema, rpc_action)}[];

              export type #{infer_result_type_name}<
                Fields extends #{fields_type_name} | undefined,
              > = Array<InferResult<#{typed_map_schema}, Fields>>;
              """
            else
              """
              export type #{fields_type_name} = #{unified_field_selection_ref(typed_map_schema, rpc_action)}[];

              export type #{infer_result_type_name}<
                Fields extends #{fields_type_name} | undefined,
              > = InferResult<#{typed_map_schema}, Fields>;
              """
            end

          {:ok, :typed_struct, _} ->
            typed_map_schema = action.returns |> return_container() |> build_map_type()

            """
            export type #{fields_type_name} = #{unified_field_selection_ref(typed_map_schema, rpc_action)}[];

            export type #{infer_result_type_name}<
              Fields extends #{fields_type_name} | undefined,
            > = InferResult<#{typed_map_schema}, Fields>;
            """

          {:ok, :array_of_typed_struct, _} ->
            typed_map_schema = action.returns |> return_container() |> build_map_type()

            """
            export type #{fields_type_name} = #{unified_field_selection_ref(typed_map_schema, rpc_action)}[];

            export type #{infer_result_type_name}<
              Fields extends #{fields_type_name} | undefined,
            > = Array<InferResult<#{typed_map_schema}, Fields>>;
            """

          {:ok, :unconstrained_map, _} ->
            """
            export type #{infer_result_type_name} = Record<string, any>;
            """

          {:ok, :array_of_unconstrained_map, _} ->
            """
            export type #{infer_result_type_name} = Array<Record<string, any>>;
            """

          _ ->
            if action.returns do
              return_type = AshTypescript.Codegen.TypeMapper.map_type(action.returns, [], :output)

              """
              export type #{infer_result_type_name} = #{return_type};
              """
            else
              """
              export type #{infer_result_type_name} = {};
              """
            end
        end
    end
  end

  # Emits explicit F/S type arguments only when a flag is disabled, keeping
  # default output byte-identical for unaffected actions. Nested envelope
  # gating is flags-only, so this reads the raw enable flags rather than
  # supports_filtering/supports_sorting (which also encode the read/get gate).
  defp unified_field_selection_ref(schema_ref, rpc_action) do
    entrypoint = EntrypointOptions.entrypoint!(rpc_action)

    case {EntrypointOptions.filter_enabled?(entrypoint),
          EntrypointOptions.sort_enabled?(entrypoint)} do
      {true, true} -> "UnifiedFieldSelection<#{schema_ref}>"
      {f, s} -> "UnifiedFieldSelection<#{schema_ref}, #{f}, #{s}>"
    end
  end

  # The decorated typed container an action returns (an array's item type), with
  # `:type_ref`s resolved, so field names come from its decoration. The return
  # classification only selects the code path.
  defp return_container(%Ash.Info.Manifest.Type{kind: :array, item_type: item}),
    do: ClientNames.resolve_type!(item)

  defp return_container(%Ash.Info.Manifest.Type{} = type), do: ClientNames.resolve_type!(type)
end
