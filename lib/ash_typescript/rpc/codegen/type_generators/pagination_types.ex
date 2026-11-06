# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen.TypeGenerators.PaginationTypes do
  @moduledoc """
  Generates TypeScript pagination result types for RPC actions.

  Supports:
  - Offset pagination (limit/offset)
  - Keyset pagination (limit/after/before)
  - Mixed pagination (both offset and keyset)
  - Conditional pagination (optional pagination)
  """

  import AshTypescript.Helpers

  alias AshTypescript.Rpc.Codegen.FunctionNames
  alias AshTypescript.Rpc.Codegen.Helpers.ActionIntrospection

  @doc """
  Generates the pagination result type based on the action's pagination support.

  This function is used when pagination is required (not optional).

  ## Parameters

    * `_resource` - The Ash resource (unused but kept for consistency)
    * `action` - The Ash action
    * `rpc_action_name` - The name of the RPC action
    * `schema_ref` - The TypeScript resource type name
    * `has_metadata` - Boolean indicating if metadata is enabled

  ## Returns

  A string containing the TypeScript result type definition for the appropriate pagination type.
  """
  def generate_pagination_result_type(
        _resource,
        action,
        rpc_action_name,
        schema_ref,
        has_metadata
      ) do
    supports_offset = ActionIntrospection.action_supports_offset_pagination?(action)
    supports_keyset = ActionIntrospection.action_supports_keyset_pagination?(action)

    cond do
      supports_offset and supports_keyset ->
        generate_mixed_pagination_result_type(rpc_action_name, schema_ref, has_metadata)

      supports_offset ->
        generate_offset_pagination_result_type(
          rpc_action_name,
          schema_ref,
          has_metadata
        )

      supports_keyset ->
        generate_keyset_pagination_result_type(
          rpc_action_name,
          schema_ref,
          has_metadata
        )
    end
  end

  defp generate_offset_pagination_result_type(rpc_action_name, schema_ref, has_metadata) do
    infer_result_type_name = FunctionNames.infer_result_type(rpc_action_name)
    fields_type_name = FunctionNames.fields_type(rpc_action_name)
    metadata_type_name = FunctionNames.metadata_type(rpc_action_name)

    results_field = formatted_results_field()
    has_more_field = formatted_has_more_field()
    limit_field = formatted_limit_field()
    offset_field = formatted_offset_field()
    count_field = formatted_count_field()
    type_field = format_output_field(:type)

    if has_metadata do
      """
      export type #{infer_result_type_name}<
        Fields extends #{fields_type_name},
        MetadataFields extends ReadonlyArray<keyof #{metadata_type_name}> = []
      > = {
        #{results_field}: Array<InferResult<#{schema_ref}, Fields> & Pick<#{metadata_type_name}, MetadataFields[number]>>;
        #{has_more_field}: boolean;
        #{limit_field}: number;
        #{offset_field}: number;
        #{count_field}?: number | null;
        #{type_field}: "offset";
      };
      """
    else
      """
      export type #{infer_result_type_name}<
        Fields extends #{fields_type_name},
      > = {
        #{results_field}: Array<InferResult<#{schema_ref}, Fields>>;
        #{has_more_field}: boolean;
        #{limit_field}: number;
        #{offset_field}: number;
        #{count_field}?: number | null;
        #{type_field}: "offset";
      };
      """
    end
  end

  defp generate_keyset_pagination_result_type(rpc_action_name, schema_ref, has_metadata) do
    infer_result_type_name = FunctionNames.infer_result_type(rpc_action_name)
    fields_type_name = FunctionNames.fields_type(rpc_action_name)
    metadata_type_name = FunctionNames.metadata_type(rpc_action_name)

    results_field = formatted_results_field()
    has_more_field = formatted_has_more_field()
    limit_field = formatted_limit_field()
    after_field = formatted_after_field()
    before_field = formatted_before_field()
    previous_page_field = formatted_previous_page_field()
    next_page_field = formatted_next_page_field()
    count_field = formatted_count_field()
    type_field = format_output_field(:type)

    if has_metadata do
      """
      export type #{infer_result_type_name}<
        Fields extends #{fields_type_name},
        MetadataFields extends ReadonlyArray<keyof #{metadata_type_name}> = []
      > = {
        #{results_field}: Array<InferResult<#{schema_ref}, Fields> & Pick<#{metadata_type_name}, MetadataFields[number]>>;
        #{has_more_field}: boolean;
        #{limit_field}: number;
        #{after_field}: string | null;
        #{before_field}: string | null;
        #{previous_page_field}: string | null;
        #{next_page_field}: string | null;
        #{count_field}?: number | null;
        #{type_field}: "keyset";
      };
      """
    else
      """
      export type #{infer_result_type_name}<
        Fields extends #{fields_type_name},
      > = {
        #{results_field}: Array<InferResult<#{schema_ref}, Fields>>;
        #{has_more_field}: boolean;
        #{limit_field}: number;
        #{after_field}: string | null;
        #{before_field}: string | null;
        #{previous_page_field}: string | null;
        #{next_page_field}: string | null;
        #{count_field}?: number | null;
        #{type_field}: "keyset";
      };
      """
    end
  end

  defp generate_mixed_pagination_result_type(rpc_action_name, schema_ref, has_metadata) do
    infer_result_type_name = FunctionNames.infer_result_type(rpc_action_name)
    fields_type_name = FunctionNames.fields_type(rpc_action_name)
    metadata_type_name = FunctionNames.metadata_type(rpc_action_name)

    results_field = formatted_results_field()
    has_more_field = formatted_has_more_field()
    limit_field = formatted_limit_field()
    offset_field = formatted_offset_field()
    after_field = formatted_after_field()
    before_field = formatted_before_field()
    count_field = formatted_count_field()
    previous_page_field = formatted_previous_page_field()
    next_page_field = formatted_next_page_field()
    type_field = format_output_field(:type)

    if has_metadata do
      """
      export type #{infer_result_type_name}<
        Fields extends #{fields_type_name},
        MetadataFields extends ReadonlyArray<keyof #{metadata_type_name}> = []
      > = {
        #{results_field}: Array<InferResult<#{schema_ref}, Fields> & Pick<#{metadata_type_name}, MetadataFields[number]>>;
        #{has_more_field}: boolean;
        #{limit_field}: number;
        #{offset_field}: number;
        #{count_field}?: number | null;
        #{type_field}: "offset";
      } | {
        #{results_field}: Array<InferResult<#{schema_ref}, Fields> & Pick<#{metadata_type_name}, MetadataFields[number]>>;
        #{has_more_field}: boolean;
        #{limit_field}: number;
        #{after_field}: string | null;
        #{before_field}: string | null;
        #{previous_page_field}: string | null;
        #{next_page_field}: string | null;
        #{count_field}?: number | null;
        #{type_field}: "keyset";
      };
      """
    else
      """
      export type #{infer_result_type_name}<
        Fields extends #{fields_type_name},
      > = {
        #{results_field}: Array<InferResult<#{schema_ref}, Fields>>;
        #{has_more_field}: boolean;
        #{limit_field}: number;
        #{offset_field}: number;
        #{count_field}?: number | null;
        #{type_field}: "offset";
      } | {
        #{results_field}: Array<InferResult<#{schema_ref}, Fields>>;
        #{has_more_field}: boolean;
        #{limit_field}: number;
        #{after_field}: string | null;
        #{before_field}: string | null;
        #{previous_page_field}: string | null;
        #{next_page_field}: string | null;
        #{count_field}?: number | null;
        #{type_field}: "keyset";
      };
      """
    end
  end

  @doc """
  Generates a conditional pagination result type (pagination is optional).

  Uses TypeScript conditional types to return either a plain array (no pagination)
  or a paginated result based on the presence of the `page` config parameter.

  ## Parameters

    * `_resource` - The Ash resource (unused but kept for consistency)
    * `action` - The Ash action
    * `rpc_action_name` - The name of the RPC action
    * `schema_ref` - The TypeScript resource type name
    * `has_metadata` - Boolean indicating if metadata is enabled

  ## Returns

  A string containing the TypeScript conditional result type definition.
  """
  def generate_conditional_pagination_result_type(
        _resource,
        action,
        rpc_action_name,
        schema_ref,
        has_metadata
      ) do
    infer_result_type_name = FunctionNames.infer_result_type(rpc_action_name)
    fields_type_name = FunctionNames.fields_type(rpc_action_name)
    config_type_name = FunctionNames.config_type(rpc_action_name)
    metadata_type_name = FunctionNames.metadata_type(rpc_action_name)

    supports_offset = ActionIntrospection.action_supports_offset_pagination?(action)
    supports_keyset = ActionIntrospection.action_supports_keyset_pagination?(action)

    if has_metadata do
      array_type =
        "Array<InferResult<#{schema_ref}, Fields> & Pick<#{metadata_type_name}, MetadataFields[number]>>"

      cond do
        supports_offset and supports_keyset ->
          offset_type =
            generate_offset_pagination_type_inline(
              schema_ref,
              rpc_action_name,
              has_metadata
            )

          keyset_type =
            generate_keyset_pagination_type_inline(
              schema_ref,
              rpc_action_name,
              has_metadata
            )

          """
          export type #{infer_result_type_name}<
            Fields extends #{fields_type_name} | undefined,
            MetadataFields extends ReadonlyArray<keyof #{metadata_type_name}> = [],
            Page extends #{config_type_name}["#{formatted_page_field()}"] = undefined
          > = ConditionalPaginatedResultMixed<Page, #{array_type}, #{offset_type}, #{keyset_type}>;
          """

        supports_offset ->
          offset_type =
            generate_offset_pagination_type_inline(
              schema_ref,
              rpc_action_name,
              has_metadata
            )

          """
          export type #{infer_result_type_name}<
            Fields extends #{fields_type_name} | undefined,
            MetadataFields extends ReadonlyArray<keyof #{metadata_type_name}> = [],
            Page extends #{config_type_name}["#{formatted_page_field()}"] = undefined
          > = ConditionalPaginatedResult<Page, #{array_type}, #{offset_type}>;
          """

        supports_keyset ->
          keyset_type =
            generate_keyset_pagination_type_inline(
              schema_ref,
              rpc_action_name,
              has_metadata
            )

          """
          export type #{infer_result_type_name}<
            Fields extends #{fields_type_name} | undefined,
            MetadataFields extends ReadonlyArray<keyof #{metadata_type_name}> = [],
            Page extends #{config_type_name}["#{formatted_page_field()}"] = undefined
          > = ConditionalPaginatedResult<Page, #{array_type}, #{keyset_type}>;
          """
      end
    else
      array_type = "Array<InferResult<#{schema_ref}, Fields>>"

      cond do
        supports_offset and supports_keyset ->
          offset_type =
            generate_offset_pagination_type_inline(
              schema_ref,
              rpc_action_name,
              has_metadata
            )

          keyset_type =
            generate_keyset_pagination_type_inline(
              schema_ref,
              rpc_action_name,
              has_metadata
            )

          """
          export type #{infer_result_type_name}<
            Fields extends #{fields_type_name} | undefined,
            Page extends #{config_type_name}["#{formatted_page_field()}"] = undefined
          > = ConditionalPaginatedResultMixed<Page, #{array_type}, #{offset_type}, #{keyset_type}>;
          """

        supports_offset ->
          offset_type =
            generate_offset_pagination_type_inline(
              schema_ref,
              rpc_action_name,
              has_metadata
            )

          """
          export type #{infer_result_type_name}<
            Fields extends #{fields_type_name} | undefined,
            Page extends #{config_type_name}["#{formatted_page_field()}"] = undefined
          > = ConditionalPaginatedResult<Page, #{array_type}, #{offset_type}>;
          """

        supports_keyset ->
          keyset_type =
            generate_keyset_pagination_type_inline(
              schema_ref,
              rpc_action_name,
              has_metadata
            )

          """
          export type #{infer_result_type_name}<
            Fields extends #{fields_type_name} | undefined,
            Page extends #{config_type_name}["#{formatted_page_field()}"] = undefined
          > = ConditionalPaginatedResult<Page, #{array_type}, #{keyset_type}>;
          """
      end
    end
  end

  defp generate_offset_pagination_type_inline(schema_ref, rpc_action_name, has_metadata) do
    metadata_type_name = FunctionNames.metadata_type(rpc_action_name)

    results_field = formatted_results_field()
    has_more_field = formatted_has_more_field()
    limit_field = formatted_limit_field()
    offset_field = formatted_offset_field()
    count_field = formatted_count_field()
    type_field = format_output_field(:type)

    result_array_type =
      if has_metadata do
        "Array<InferResult<#{schema_ref}, Fields> & Pick<#{metadata_type_name}, MetadataFields[number]>>"
      else
        "Array<InferResult<#{schema_ref}, Fields>>"
      end

    """
    {
      #{results_field}: #{result_array_type};
      #{has_more_field}: boolean;
      #{limit_field}: number;
      #{offset_field}: number;
      #{count_field}?: number | null;
      #{type_field}: "offset";
    }
    """
    |> String.trim()
  end

  defp generate_keyset_pagination_type_inline(schema_ref, rpc_action_name, has_metadata) do
    metadata_type_name = FunctionNames.metadata_type(rpc_action_name)

    results_field = formatted_results_field()
    has_more_field = formatted_has_more_field()
    limit_field = formatted_limit_field()
    after_field = formatted_after_field()
    before_field = formatted_before_field()
    previous_page_field = formatted_previous_page_field()
    next_page_field = formatted_next_page_field()
    count_field = formatted_count_field()
    type_field = format_output_field(:type)

    result_array_type =
      if has_metadata do
        "Array<InferResult<#{schema_ref}, Fields> & Pick<#{metadata_type_name}, MetadataFields[number]>>"
      else
        "Array<InferResult<#{schema_ref}, Fields>>"
      end

    """
    {
      #{results_field}: #{result_array_type};
      #{has_more_field}: boolean;
      #{limit_field}: number;
      #{after_field}: string | null;
      #{before_field}: string | null;
      #{previous_page_field}: string | null;
      #{next_page_field}: string | null;
      #{count_field}?: number | null;
      #{type_field}: "keyset";
    }
    """
    |> String.trim()
  end
end
