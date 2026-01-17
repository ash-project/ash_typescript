# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
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

  alias AshTypescript.Rpc.Codegen.Helpers.ActionIntrospection

  @doc """
  Generates the pagination result type based on the action's pagination support.

  This function is used when pagination is required (not optional).

  ## Parameters

    * `_resource` - The Ash resource (unused but kept for consistency)
    * `action` - The Ash action
    * `rpc_action_name_pascal` - The PascalCase name of the RPC action
    * `schema_ref` - The TypeScript resource type name
    * `has_metadata` - Boolean indicating if metadata is enabled

  ## Returns

  A string containing the TypeScript result type definition for the appropriate pagination type.
  """
  def generate_pagination_result_type(
        _resource,
        action,
        rpc_action_name_pascal,
        schema_ref,
        has_metadata
      ) do
    supports_offset = ActionIntrospection.action_supports_offset_pagination?(action)
    supports_keyset = ActionIntrospection.action_supports_keyset_pagination?(action)

    cond do
      supports_offset and supports_keyset ->
        generate_mixed_pagination_result_type(rpc_action_name_pascal, schema_ref, has_metadata)

      supports_offset ->
        generate_offset_pagination_result_type(
          rpc_action_name_pascal,
          schema_ref,
          has_metadata
        )

      supports_keyset ->
        generate_keyset_pagination_result_type(
          rpc_action_name_pascal,
          schema_ref,
          has_metadata
        )
    end
  end

  @doc """
  Generates an offset pagination result type.

  The result includes:
  - results: Array of items
  - hasMore: Boolean indicating if more results exist
  - limit: Number of items per page
  - offset: Current offset
  """
  def generate_offset_pagination_result_type(rpc_action_name_pascal, schema_ref, has_metadata) do
    results_field = formatted_results_field()
    has_more_field = formatted_has_more_field()
    limit_field = formatted_limit_field()
    offset_field = formatted_offset_field()

    if has_metadata do
      """
      export type Infer#{rpc_action_name_pascal}Result<
        Fields extends #{rpc_action_name_pascal}Fields,
        MetadataFields extends ReadonlyArray<keyof #{rpc_action_name_pascal}Metadata> = []
      > = {
        #{results_field}: Array<InferResult<#{schema_ref}, Fields> & Pick<#{rpc_action_name_pascal}Metadata, MetadataFields[number]>>;
        #{has_more_field}: boolean;
        #{limit_field}: number;
        #{offset_field}: number;
      };
      """
    else
      """
      export type Infer#{rpc_action_name_pascal}Result<
        Fields extends #{rpc_action_name_pascal}Fields,
      > = {
        #{results_field}: Array<InferResult<#{schema_ref}, Fields>>;
        #{has_more_field}: boolean;
        #{limit_field}: number;
        #{offset_field}: number;
      };
      """
    end
  end

  @doc """
  Generates a keyset pagination result type.

  The result includes:
  - results: Array of items
  - hasMore: Boolean indicating if more results exist
  - limit: Number of items per page
  - after: Cursor for next page (or null)
  - before: Cursor for previous page (or null)
  - previousPage: Cursor string for previous page
  - nextPage: Cursor string for next page
  """
  def generate_keyset_pagination_result_type(rpc_action_name_pascal, schema_ref, has_metadata) do
    results_field = formatted_results_field()
    has_more_field = formatted_has_more_field()
    limit_field = formatted_limit_field()
    after_field = formatted_after_field()
    before_field = formatted_before_field()
    previous_page_field = formatted_previous_page_field()
    next_page_field = formatted_next_page_field()

    if has_metadata do
      """
      export type Infer#{rpc_action_name_pascal}Result<
        Fields extends #{rpc_action_name_pascal}Fields,
        MetadataFields extends ReadonlyArray<keyof #{rpc_action_name_pascal}Metadata> = []
      > = {
        #{results_field}: Array<InferResult<#{schema_ref}, Fields> & Pick<#{rpc_action_name_pascal}Metadata, MetadataFields[number]>>;
        #{has_more_field}: boolean;
        #{limit_field}: number;
        #{after_field}: string | null;
        #{before_field}: string | null;
        #{previous_page_field}: string;
        #{next_page_field}: string;
      };
      """
    else
      """
      export type Infer#{rpc_action_name_pascal}Result<
        Fields extends #{rpc_action_name_pascal}Fields,
      > = {
        #{results_field}: Array<InferResult<#{schema_ref}, Fields>>;
        #{has_more_field}: boolean;
        #{limit_field}: number;
        #{after_field}: string | null;
        #{before_field}: string | null;
        #{previous_page_field}: string;
        #{next_page_field}: string;
      };
      """
    end
  end

  @doc """
  Generates a mixed pagination result type (supports both offset and keyset).

  The result is a union type with a discriminant `type` field that indicates
  whether offset or keyset pagination was used.
  """
  def generate_mixed_pagination_result_type(rpc_action_name_pascal, schema_ref, has_metadata) do
    results_field = formatted_results_field()
    has_more_field = formatted_has_more_field()
    limit_field = formatted_limit_field()
    offset_field = formatted_offset_field()
    after_field = formatted_after_field()
    before_field = formatted_before_field()
    count_field = format_output_field(:count)
    previous_page_field = formatted_previous_page_field()
    next_page_field = formatted_next_page_field()
    type_field = format_output_field(:type)

    if has_metadata do
      """
      export type Infer#{rpc_action_name_pascal}Result<
        Fields extends #{rpc_action_name_pascal}Fields,
        MetadataFields extends ReadonlyArray<keyof #{rpc_action_name_pascal}Metadata> = []
      > = {
        #{results_field}: Array<InferResult<#{schema_ref}, Fields> & Pick<#{rpc_action_name_pascal}Metadata, MetadataFields[number]>>;
        #{has_more_field}: boolean;
        #{limit_field}: number;
        #{offset_field}: number;
        #{count_field}?: number | null;
        #{type_field}: "offset";
      } | {
        #{results_field}: Array<InferResult<#{schema_ref}, Fields> & Pick<#{rpc_action_name_pascal}Metadata, MetadataFields[number]>>;
        #{has_more_field}: boolean;
        #{limit_field}: number;
        #{after_field}: string | null;
        #{before_field}: string | null;
        #{previous_page_field}: string;
        #{next_page_field}: string;
        #{count_field}?: number | null;
        #{type_field}: "keyset";
      };
      """
    else
      """
      export type Infer#{rpc_action_name_pascal}Result<
        Fields extends #{rpc_action_name_pascal}Fields,
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
        #{previous_page_field}: string;
        #{next_page_field}: string;
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
    * `rpc_action_name_pascal` - The PascalCase name of the RPC action
    * `schema_ref` - The TypeScript resource type name
    * `has_metadata` - Boolean indicating if metadata is enabled

  ## Returns

  A string containing the TypeScript conditional result type definition.
  """
  def generate_conditional_pagination_result_type(
        _resource,
        action,
        rpc_action_name_pascal,
        schema_ref,
        has_metadata
      ) do
    supports_offset = ActionIntrospection.action_supports_offset_pagination?(action)
    supports_keyset = ActionIntrospection.action_supports_keyset_pagination?(action)

    if has_metadata do
      array_type =
        "Array<InferResult<#{schema_ref}, Fields> & Pick<#{rpc_action_name_pascal}Metadata, MetadataFields[number]>>"

      cond do
        supports_offset and supports_keyset ->
          offset_type =
            generate_offset_pagination_type_inline(
              schema_ref,
              rpc_action_name_pascal,
              has_metadata
            )

          keyset_type =
            generate_keyset_pagination_type_inline(
              schema_ref,
              rpc_action_name_pascal,
              has_metadata
            )

          """
          export type Infer#{rpc_action_name_pascal}Result<
            Fields extends #{rpc_action_name_pascal}Fields | undefined,
            MetadataFields extends ReadonlyArray<keyof #{rpc_action_name_pascal}Metadata> = [],
            Page extends #{rpc_action_name_pascal}Config["page"] = undefined
          > = ConditionalPaginatedResultMixed<Page, #{array_type}, #{offset_type}, #{keyset_type}>;
          """

        supports_offset ->
          offset_type =
            generate_offset_pagination_type_inline(
              schema_ref,
              rpc_action_name_pascal,
              has_metadata
            )

          """
          export type Infer#{rpc_action_name_pascal}Result<
            Fields extends #{rpc_action_name_pascal}Fields | undefined,
            MetadataFields extends ReadonlyArray<keyof #{rpc_action_name_pascal}Metadata> = [],
            Page extends #{rpc_action_name_pascal}Config["page"] = undefined
          > = ConditionalPaginatedResult<Page, #{array_type}, #{offset_type}>;
          """

        supports_keyset ->
          keyset_type =
            generate_keyset_pagination_type_inline(
              schema_ref,
              rpc_action_name_pascal,
              has_metadata
            )

          """
          export type Infer#{rpc_action_name_pascal}Result<
            Fields extends #{rpc_action_name_pascal}Fields | undefined,
            MetadataFields extends ReadonlyArray<keyof #{rpc_action_name_pascal}Metadata> = [],
            Page extends #{rpc_action_name_pascal}Config["page"] = undefined
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
              rpc_action_name_pascal,
              has_metadata
            )

          keyset_type =
            generate_keyset_pagination_type_inline(
              schema_ref,
              rpc_action_name_pascal,
              has_metadata
            )

          """
          export type Infer#{rpc_action_name_pascal}Result<
            Fields extends #{rpc_action_name_pascal}Fields | undefined,
            Page extends #{rpc_action_name_pascal}Config["page"] = undefined
          > = ConditionalPaginatedResultMixed<Page, #{array_type}, #{offset_type}, #{keyset_type}>;
          """

        supports_offset ->
          offset_type =
            generate_offset_pagination_type_inline(
              schema_ref,
              rpc_action_name_pascal,
              has_metadata
            )

          """
          export type Infer#{rpc_action_name_pascal}Result<
            Fields extends #{rpc_action_name_pascal}Fields | undefined,
            Page extends #{rpc_action_name_pascal}Config["page"] = undefined
          > = ConditionalPaginatedResult<Page, #{array_type}, #{offset_type}>;
          """

        supports_keyset ->
          keyset_type =
            generate_keyset_pagination_type_inline(
              schema_ref,
              rpc_action_name_pascal,
              has_metadata
            )

          """
          export type Infer#{rpc_action_name_pascal}Result<
            Fields extends #{rpc_action_name_pascal}Fields | undefined,
            Page extends #{rpc_action_name_pascal}Config["page"] = undefined
          > = ConditionalPaginatedResult<Page, #{array_type}, #{keyset_type}>;
          """
      end
    end
  end

  @doc """
  Generates an inline offset pagination type (without the wrapper Result type).

  Used within conditional pagination types.
  """
  def generate_offset_pagination_type_inline(schema_ref, rpc_action_name_pascal, has_metadata) do
    results_field = formatted_results_field()
    has_more_field = formatted_has_more_field()
    limit_field = formatted_limit_field()
    offset_field = formatted_offset_field()
    count_field = format_output_field(:count)
    type_field = format_output_field(:type)

    result_array_type =
      if has_metadata do
        "Array<InferResult<#{schema_ref}, Fields> & Pick<#{rpc_action_name_pascal}Metadata, MetadataFields[number]>>"
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

  @doc """
  Generates an inline keyset pagination type (without the wrapper Result type).

  Used within conditional pagination types.
  """
  def generate_keyset_pagination_type_inline(schema_ref, rpc_action_name_pascal, has_metadata) do
    results_field = formatted_results_field()
    has_more_field = formatted_has_more_field()
    limit_field = formatted_limit_field()
    after_field = formatted_after_field()
    before_field = formatted_before_field()
    previous_page_field = formatted_previous_page_field()
    next_page_field = formatted_next_page_field()
    count_field = format_output_field(:count)
    type_field = format_output_field(:type)

    result_array_type =
      if has_metadata do
        "Array<InferResult<#{schema_ref}, Fields> & Pick<#{rpc_action_name_pascal}Metadata, MetadataFields[number]>>"
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
      #{previous_page_field}: string;
      #{next_page_field}: string;
      #{count_field}?: number | null;
      #{type_field}: "keyset";
    }
    """
    |> String.trim()
  end
end
