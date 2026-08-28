# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.UtilityTypes do
  @moduledoc """
  Generates TypeScript utility types for field selection and type inference.

  These types are shared between RPC and typed controller code generation,
  including TypedSchema, UnionToIntersection, InferResult, pagination helpers,
  and error types.
  """

  import AshTypescript.Helpers

  @doc """
  Generates TypeScript utility types for field selection and type inference.

  Includes:
  - TypedSchema constraint
  - UnionToIntersection helper
  - InferUnionFieldValue helper
  - Field selection types
  - InferResult type
  - Pagination conditional types
  - SuccessDataFunc and ErrorData helpers
  - AshRpcError type
  """
  def generate_utility_types do
    """
    // Utility Types

    // Sort string type — allows optional direction prefix on sort field names
    // Prefixes per Ash.Query.sort/3: + (asc), - (desc), ++ (asc_nils_first), -- (desc_nils_last)
    export type SortString<T extends string> = T | `+${T}` | `-${T}` | `++${T}` | `--${T}`;

    // Nested relationship pagination input, keyed by the relationship's
    // __pagination marker ("offset" | "keyset" | "mixed"). Keys of the other
    // pagination family are typed `never` so passing them is a structural
    // error (excess-property checking does not fire through the envelope's
    // conditional types).
    export type NestedPageInput<P extends string> = P extends "offset"
      ? { #{formatted_limit_field()}?: number; #{formatted_offset_field()}?: number; #{formatted_count_field()}?: boolean; #{formatted_after_field()}?: never; #{formatted_before_field()}?: never }
      : P extends "keyset"
        ? { #{formatted_limit_field()}?: number; #{formatted_after_field()}?: string; #{formatted_before_field()}?: string; #{formatted_count_field()}?: boolean; #{formatted_offset_field()}?: never }
        :
            | { #{formatted_limit_field()}?: number; #{formatted_offset_field()}?: number; #{formatted_count_field()}?: boolean; #{formatted_after_field()}?: never; #{formatted_before_field()}?: never }
            | { #{formatted_limit_field()}?: number; #{formatted_after_field()}?: string; #{formatted_before_field()}?: string; #{formatted_count_field()}?: boolean; #{formatted_offset_field()}?: never };

    // Resource schema constraint
    export type TypedSchema = {
      __type: "Resource" | "TypedMap" | "Union";
      __primitiveFields: string;
    };

    // Utility type to convert union to intersection
    export type UnionToIntersection<U> = (U extends any ? (k: U) => void : never) extends (
      k: infer I,
    ) => void
      ? I
      : never;

    // Helper type to infer union field values, avoiding duplication between array and non-array unions
    // Selection-object walkers use key remapping to drop keys whose value is
    // undefined: hoisting a selection with `satisfies` widens the array to a
    // union whose object members grow synthetic `?: undefined` siblings, and
    // walking those as real selections would collapse the result to never.
    // `FieldSelection[FieldIndex] extends infer Sel` re-binds the element to a
    // naked type parameter so widened (non-tuple) selections distribute over
    // their element union instead of falling through to never.
    export type InferUnionFieldValue<
      UnionSchema extends { __type: "Union"; __primitiveFields: any },
      FieldSelection extends any[],
    > = UnionToIntersection<
      {
        [FieldIndex in keyof FieldSelection]: FieldSelection[FieldIndex] extends infer Sel
          ? Sel extends UnionSchema["__primitiveFields"]
            ? Sel extends keyof UnionSchema
              ? { [P in Sel]: UnionSchema[Sel] }
              : never
            : Sel extends Record<string, any>
              ? {
                  [UnionKey in keyof Sel as Sel[UnionKey] extends undefined ? never : UnionKey]: UnionKey extends keyof UnionSchema
                    ? NonNullable<UnionSchema[UnionKey]> extends { __array: true; __type: "TypedMap"; __primitiveFields: infer TypedMapFields }
                      ? Sel[UnionKey] extends any[]
                        ? Array<
                            UnionToIntersection<
                              {
                                [FieldIdx in keyof Sel[UnionKey]]: Sel[UnionKey][FieldIdx] extends TypedMapFields
                                  ? Sel[UnionKey][FieldIdx] extends keyof NonNullable<UnionSchema[UnionKey]>
                                    ? { [P in Sel[UnionKey][FieldIdx]]: NonNullable<UnionSchema[UnionKey]>[P] }
                                    : never
                                  : never;
                              }[number]
                            >
                          > | null
                        : never
                      : NonNullable<UnionSchema[UnionKey]> extends { __type: "TypedMap"; __primitiveFields: infer TypedMapFields }
                        ? Sel[UnionKey] extends any[]
                          ? UnionToIntersection<
                              {
                                [FieldIdx in keyof Sel[UnionKey]]: Sel[UnionKey][FieldIdx] extends TypedMapFields
                                  ? Sel[UnionKey][FieldIdx] extends keyof NonNullable<UnionSchema[UnionKey]>
                                    ? { [P in Sel[UnionKey][FieldIdx]]: NonNullable<UnionSchema[UnionKey]>[P] }
                                    : never
                                  : never;
                              }[number]
                            > | null
                          : never
                        : NonNullable<UnionSchema[UnionKey]> extends TypedSchema
                          ? InferResult<NonNullable<UnionSchema[UnionKey]>, Sel[UnionKey]>
                          : never
                    : never;
                }
              : never
          : never;
      }[number]
    >;

    export type HasComplexFields<T extends TypedSchema> = keyof Omit<
      T,
      "__primitiveFields" | "__type" | T["__primitiveFields"]
    > extends never
      ? false
      : true;

    export type ComplexFieldKeys<T extends TypedSchema> = keyof Omit<
      T,
      "__primitiveFields" | "__type" | T["__primitiveFields"]
    >;

    export type LeafFieldSelection<T extends TypedSchema> = T["__primitiveFields"];

    // Query-option envelope for many-cardinality relationships. Each optional
    // key is usable only when the corresponding capability marker is present
    // and the action-level flag (F = filter, S = sort) is enabled; otherwise
    // the key is typed `never` so passing a value is a structural error (plain
    // excess-property checking does not fire through these conditional types).
    // `page` and bare `limit`/`offset` are mutually exclusive: the pagination
    // part is a union of the two shapes, each `never`-typing the other's keys.
    export type RelationshipQueryEnvelope<
      Meta,
      Dest extends TypedSchema,
      F extends boolean = true,
      S extends boolean = true,
    > = {
      #{formatted_fields_field()}: UnifiedFieldSelection<Dest, F, S>[];
    } & (F extends true
      ? Meta extends { __filterInput: infer FI }
        ? { #{formatted_filter_field()}?: FI }
        : { #{formatted_filter_field()}?: never }
      : { #{formatted_filter_field()}?: never }) &
      (S extends true
        ? Meta extends { __sortField: infer SF extends string }
          ? { #{formatted_sort_field()}?: SortString<SF> | SortString<SF>[] }
          : { #{formatted_sort_field()}?: never }
        : { #{formatted_sort_field()}?: never }) &
      (Meta extends { __pagination: infer P extends string }
        ? (
            | { #{formatted_page_field()}?: NestedPageInput<P>; #{formatted_limit_field()}?: never; #{formatted_offset_field()}?: never }
            | { #{formatted_limit_field()}?: number; #{formatted_offset_field()}?: number; #{formatted_page_field()}?: never }
          )
        : { #{formatted_limit_field()}?: number; #{formatted_offset_field()}?: number; #{formatted_page_field()}?: never });

    export type ComplexFieldSelection<
      T extends TypedSchema,
      F extends boolean = true,
      S extends boolean = true,
    > = {
      [K in ComplexFieldKeys<T>]?: T[K] extends {
        __type: "Relationship";
        __resource: infer Resource;
      }
        ? NonNullable<Resource> extends TypedSchema
          ? T[K] extends { __array: true }
            ?
                | UnifiedFieldSelection<NonNullable<Resource>, F, S>[]
                | RelationshipQueryEnvelope<T[K], NonNullable<Resource>, F, S>
            : UnifiedFieldSelection<NonNullable<Resource>, F, S>[]
          : never
        : T[K] extends {
              __type: "ComplexCalculation";
              __returnType: infer ReturnType;
            }
          ? T[K] extends { __args: infer Args }
            ? NonNullable<ReturnType> extends TypedSchema
              ? {
                  #{formatted_args_field()}: Args;
                  #{formatted_fields_field()}: UnifiedFieldSelection<NonNullable<ReturnType>, F, S>[];
                }
              : { #{formatted_args_field()}: Args }
            : NonNullable<ReturnType> extends TypedSchema
              ? { #{formatted_fields_field()}: UnifiedFieldSelection<NonNullable<ReturnType>, F, S>[] }
              : never
          : T[K] extends { __type: "TypedMap" }
            ? NonNullable<T[K]> extends TypedSchema
              ? UnifiedFieldSelection<NonNullable<T[K]>, F, S>[]
              : never
            : T[K] extends { __type: "Union"; __primitiveFields: infer PrimitiveFields }
              ? T[K] extends { __array: true }
                ? (PrimitiveFields | {
                    [UnionKey in keyof Omit<T[K], "__type" | "__primitiveFields" | "__array">]?: NonNullable<T[K][UnionKey]> extends { __type: "TypedMap"; __primitiveFields: any }
                      ? NonNullable<T[K][UnionKey]>["__primitiveFields"][]
                      : NonNullable<T[K][UnionKey]> extends TypedSchema
                        ? UnifiedFieldSelection<NonNullable<T[K][UnionKey]>, F, S>[]
                        : never;
                  })[]
                : (PrimitiveFields | {
                    [UnionKey in keyof Omit<T[K], "__type" | "__primitiveFields">]?: NonNullable<T[K][UnionKey]> extends { __type: "TypedMap"; __primitiveFields: any }
                      ? NonNullable<T[K][UnionKey]>["__primitiveFields"][]
                      : NonNullable<T[K][UnionKey]> extends TypedSchema
                        ? UnifiedFieldSelection<NonNullable<T[K][UnionKey]>, F, S>[]
                        : never;
                  })[]
                : NonNullable<T[K]> extends TypedSchema
                  ? UnifiedFieldSelection<NonNullable<T[K]>, F, S>[]
                  : never;
    };

    // Main type: Use explicit base case detection to prevent infinite recursion
    export type UnifiedFieldSelection<
      T extends TypedSchema,
      F extends boolean = true,
      S extends boolean = true,
    > =
      HasComplexFields<T> extends false
        ? LeafFieldSelection<T> // Base case: only primitives, no recursion
        : LeafFieldSelection<T> | ComplexFieldSelection<T, F, S>; // Recursive case

    // Infers the result value of one selected member inside a TypedMap:
    // Relationship-wrapped members (embedded resources) recurse through the
    // wrapped resource; plain TypedSchema members (nested TypedMaps) recurse
    // directly. The Selection guard satisfies InferResult's constraint.
    export type InferTypedMapMemberValue<M, Selection> = M extends {
      __type: "Relationship";
      __resource: infer Resource;
    }
      ? NonNullable<Resource> extends TypedSchema
        ? Selection extends UnifiedFieldSelection<NonNullable<Resource>>[] | undefined
          ? M extends { __array: true }
            ? null extends Resource
              ? Array<InferResult<NonNullable<Resource>, Selection>> | null
              : Array<InferResult<NonNullable<Resource>, Selection>>
            : null extends Resource
              ? InferResult<NonNullable<Resource>, Selection> | null
              : InferResult<NonNullable<Resource>, Selection>
          : never
        : never
      : NonNullable<M> extends TypedSchema
        ? Selection extends UnifiedFieldSelection<NonNullable<M>>[] | undefined
          ? null extends M
            ? InferResult<NonNullable<M>, Selection> | null
            : InferResult<NonNullable<M>, Selection>
          : never
        : never;

    export type InferFieldValue<
      T extends TypedSchema,
      Field,
    > = Field extends T["__primitiveFields"]
      ? Field extends keyof T
        ? { [K in Field]: T[Field] }
        : never
      : Field extends Record<string, any>
        ? {
            [K in keyof Field as Field[K] extends undefined ? never : K]: K extends keyof T
              ? T[K] extends {
                  __type: "Relationship";
                  __resource: infer Resource;
                }
                ? NonNullable<Resource> extends TypedSchema
                  ? Field[K] extends { #{formatted_fields_field()}: infer NestedFields }
                    ? NestedFields extends UnifiedFieldSelection<NonNullable<Resource>>[]
                      ? Field[K] extends { #{formatted_page_field()}: infer Page }
                        ? T[K] extends { __pagination: infer P extends string }
                          ? NestedPageResult<NonNullable<Resource>, NestedFields, P, Page>
                          : never
                        : T[K] extends { __array: true }
                          ? Array<InferResult<NonNullable<Resource>, NestedFields>>
                          : never
                      : never
                    : T[K] extends { __array: true }
                      ? null extends Resource
                        ? Array<InferResult<NonNullable<Resource>, Field[K]>> | null
                        : Array<InferResult<NonNullable<Resource>, Field[K]>>
                      : null extends Resource
                        ? InferResult<NonNullable<Resource>, Field[K]> | null
                        : InferResult<NonNullable<Resource>, Field[K]>
                : never
              : T[K] extends {
                    __type: "ComplexCalculation";
                    __returnType: infer ReturnType;
                  }
                ? NonNullable<ReturnType> extends TypedSchema
                  ? null extends ReturnType
                    ? InferResult<NonNullable<ReturnType>, Field[K]["fields"]> | null
                    : InferResult<NonNullable<ReturnType>, Field[K]["fields"]>
                  : ReturnType
                : NonNullable<T[K]> extends { __type: "TypedMap"; __primitiveFields: infer TypedMapFields }
                  ? NonNullable<T[K]> extends { __array: true }
                    ? Field[K] extends any[]
                      ? null extends T[K]
                        ? Array<
                            UnionToIntersection<
                              {
                                [FieldIndex in keyof Field[K]]: Field[K][FieldIndex] extends infer E
                                  ? E extends TypedMapFields
                                    ? E extends keyof NonNullable<T[K]>
                                      ? { [P in E]: NonNullable<T[K]>[P] }
                                      : never
                                    : E extends Record<string, any>
                                      ? {
                                          [NestedKey in keyof E as E[NestedKey] extends undefined ? never : NestedKey]: NestedKey extends keyof NonNullable<T[K]>
                                              ? InferTypedMapMemberValue<NonNullable<T[K]>[NestedKey], E[NestedKey]>
                                            : never;
                                        }
                                      : E extends keyof NonNullable<T[K]>
                                        ? { [P in E]: NonNullable<T[K]>[P] }
                                        : never
                                  : never;
                              }[number]
                            >
                          > | null
                        : Array<
                            UnionToIntersection<
                              {
                                [FieldIndex in keyof Field[K]]: Field[K][FieldIndex] extends infer E
                                  ? E extends TypedMapFields
                                    ? E extends keyof NonNullable<T[K]>
                                      ? { [P in E]: NonNullable<T[K]>[P] }
                                      : never
                                    : E extends Record<string, any>
                                      ? {
                                          [NestedKey in keyof E as E[NestedKey] extends undefined ? never : NestedKey]: NestedKey extends keyof NonNullable<T[K]>
                                              ? InferTypedMapMemberValue<NonNullable<T[K]>[NestedKey], E[NestedKey]>
                                            : never;
                                        }
                                      : E extends keyof NonNullable<T[K]>
                                        ? { [P in E]: NonNullable<T[K]>[P] }
                                        : never
                                  : never;
                              }[number]
                            >
                          >
                      : never
                    : Field[K] extends any[]
                      ? null extends T[K]
                        ? UnionToIntersection<
                            {
                              [FieldIndex in keyof Field[K]]: Field[K][FieldIndex] extends infer E
                                ? E extends TypedMapFields
                                  ? E extends keyof NonNullable<T[K]>
                                    ? { [P in E]: NonNullable<T[K]>[P] }
                                    : never
                                  : E extends Record<string, any>
                                    ? {
                                        [NestedKey in keyof E as E[NestedKey] extends undefined ? never : NestedKey]: NestedKey extends keyof NonNullable<T[K]>
                                            ? InferTypedMapMemberValue<NonNullable<T[K]>[NestedKey], E[NestedKey]>
                                          : never;
                                      }
                                    : E extends keyof NonNullable<T[K]>
                                      ? { [P in E]: NonNullable<T[K]>[P] }
                                      : never
                                : never;
                            }[number]
                          > | null
                        : UnionToIntersection<
                            {
                              [FieldIndex in keyof Field[K]]: Field[K][FieldIndex] extends infer E
                                ? E extends TypedMapFields
                                  ? E extends keyof T[K]
                                    ? { [P in E]: T[K][P] }
                                    : never
                                  : E extends Record<string, any>
                                    ? {
                                        [NestedKey in keyof E as E[NestedKey] extends undefined ? never : NestedKey]: NestedKey extends keyof NonNullable<T[K]>
                                            ? InferTypedMapMemberValue<NonNullable<T[K]>[NestedKey], E[NestedKey]>
                                          : never;
                                      }
                                    : E extends keyof NonNullable<T[K]>
                                      ? { [P in E]: NonNullable<T[K]>[P] }
                                      : never
                                : never;
                            }[number]
                          >
                      : never
                  : T[K] extends { __type: "Union"; __primitiveFields: any }
                    ? T[K] extends { __array: true }
                      ? Field[K] extends any[]
                        ? null extends T[K]
                          ? Array<InferUnionFieldValue<T[K], Field[K]>> | null
                          : Array<InferUnionFieldValue<T[K], Field[K]>>
                        : never
                      : Field[K] extends any[]
                        ? null extends T[K]
                          ? InferUnionFieldValue<T[K], Field[K]> | null
                          : InferUnionFieldValue<T[K], Field[K]>
                        : never
                      : NonNullable<T[K]> extends TypedSchema
                        ? null extends T[K]
                          ? InferResult<NonNullable<T[K]>, Field[K]> | null
                          : InferResult<NonNullable<T[K]>, Field[K]>
                        : never
              : never;
          }
        : never;

    export type InferResult<
      T extends TypedSchema,
      SelectedFields extends UnifiedFieldSelection<T>[] | undefined,
    > = SelectedFields extends undefined
      ? {}
      : SelectedFields extends []
      ? {}
      : SelectedFields extends UnifiedFieldSelection<T>[]
      ? UnionToIntersection<
          {
            [K in keyof SelectedFields]: InferFieldValue<T, SelectedFields[K]>;
          }[number]
        >
      : {};

    // Pagination conditional types
    // Checks if a page configuration object has any pagination parameters.
    // A limit-only page (e.g. { limit: 20 } for the first page) also paginates.
    export type HasPaginationParams<Page> =
      Page extends { offset: any } ? true :
      Page extends { after: any } ? true :
      Page extends { before: any } ? true :
      Page extends { limit: any } ? true :
      false;

    // Infer which pagination type is being used from the page config.
    // A limit-only page resolves to keyset — when an action supports both
    // strategies, Ash paginates limit-only requests with keyset.
    export type InferPaginationType<Page> =
      Page extends { offset: any } ? "offset" :
      Page extends { after: any } | { before: any } ? "keyset" :
      Page extends { limit: any } ? "keyset" :
      never;

    // Returns either non-paginated (array) or paginated result based on page params
    // For single pagination type support (offset-only or keyset-only)
    // @ts-ignore
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    export type ConditionalPaginatedResult<
      Page,
      RecordType,
      PaginatedType
    > = Page extends undefined
      ? RecordType
      : HasPaginationParams<Page> extends true
        ? PaginatedType
        : RecordType;

    // For actions supporting both offset and keyset pagination
    // Infers the specific pagination type based on which params were passed
    export type ConditionalPaginatedResultMixed<
      Page,
      RecordType,
      OffsetType,
      KeysetType
    > = Page extends undefined
      ? RecordType
      : HasPaginationParams<Page> extends true
        ? InferPaginationType<Page> extends "offset"
          ? OffsetType
          : InferPaginationType<Page> extends "keyset"
            ? KeysetType
            : OffsetType | KeysetType  // Fallback to union if can't determine
        : RecordType;

    // Nested relationship pagination results — shaped identically to the
    // top-level page payloads, but generic over the destination schema.
    export type NestedOffsetPageResult<R extends TypedSchema, Fields> = {
      #{formatted_results_field()}: Fields extends UnifiedFieldSelection<R>[] ? Array<InferResult<R, Fields>> : never;
      #{formatted_has_more_field()}: boolean;
      #{formatted_limit_field()}: number;
      #{formatted_offset_field()}: number;
      #{formatted_count_field()}?: number | null;
      #{format_output_field(:type)}: "offset";
    };

    export type NestedKeysetPageResult<R extends TypedSchema, Fields> = {
      #{formatted_results_field()}: Fields extends UnifiedFieldSelection<R>[] ? Array<InferResult<R, Fields>> : never;
      #{formatted_has_more_field()}: boolean;
      #{formatted_limit_field()}: number;
      #{formatted_after_field()}: string | null;
      #{formatted_before_field()}: string | null;
      #{formatted_previous_page_field()}: string | null;
      #{formatted_next_page_field()}: string | null;
      #{formatted_count_field()}?: number | null;
      #{format_output_field(:type)}: "keyset";
    };

    // P is the relationship's __pagination marker; Page is the page input the
    // caller actually passed (used to narrow "mixed" to a concrete side).
    export type NestedPageResult<R extends TypedSchema, Fields, P extends string, Page> =
      P extends "offset"
        ? NestedOffsetPageResult<R, Fields>
        : P extends "keyset"
          ? NestedKeysetPageResult<R, Fields>
          : InferPaginationType<Page> extends "offset"
            ? NestedOffsetPageResult<R, Fields>
            : InferPaginationType<Page> extends "keyset"
              ? NestedKeysetPageResult<R, Fields>
              : NestedOffsetPageResult<R, Fields> | NestedKeysetPageResult<R, Fields>;

    export type SuccessDataFunc<T extends (...args: any[]) => Promise<any>> = Extract<
      Awaited<ReturnType<T>>,
      { #{formatted_success_field()}: true }
    >["#{formatted_data_field()}"];


    export type ErrorData<T extends (...args: any[]) => Promise<any>> = Extract<
      Awaited<ReturnType<T>>,
      { #{formatted_success_field()}: false }
    >["#{formatted_errors_field()}"];

    /**
     * Represents an error from an unsuccessful RPC call.
     *
     * This type matches the error structure defined in the AshTypescript.Rpc.Error protocol.
     *
     * @example
     * const error: AshRpcError = {
     *   #{formatted_error_type_field()}: "invalid_changes",
     *   #{formatted_error_message_field()}: "Invalid value for field %{field}",
     *   #{formatted_error_short_message_field()}: "Invalid changes",
     *   #{formatted_error_vars_field()}: { field: "email" },
     *   #{formatted_error_fields_field()}: ["email"],
     *   #{formatted_error_path_field()}: ["user", "email"],
     *   #{formatted_error_details_field()}: { suggestion: "Provide a valid email address" }
     * }
     *
     * @example
     * // An internal error withholds detail and carries a correlation ID
     * const error: AshRpcError = {
     *   #{formatted_error_type_field()}: "internal_error",
     *   #{formatted_error_message_field()}: "Something went wrong. Unique error id: 4f3c...",
     *   #{formatted_error_short_message_field()}: "Internal error",
     *   #{formatted_error_vars_field()}: {},
     *   #{formatted_error_fields_field()}: [],
     *   #{formatted_error_path_field()}: [],
     *   #{formatted_error_id_field()}: "4f3c..."
     * }
     */
    export type AshRpcError = {
      /** Machine-readable error type (e.g., "invalid_changes", "not_found") */
      #{formatted_error_type_field()}: string;
      /** Full error message (may contain template variables like %{key}) */
      #{formatted_error_message_field()}: string;
      /** Concise version of the message */
      #{formatted_error_short_message_field()}: string;
      /** Variables to interpolate into the message template */
      #{formatted_error_vars_field()}: Record<string, any>;
      /** List of affected field names (for field-level errors) */
      #{formatted_error_fields_field()}: string[];
      /** Path to the error location in the data structure */
      #{formatted_error_path_field()}: string[];
      /** Optional map with extra details (e.g., suggestions, hints) */
      #{formatted_error_details_field()}?: Record<string, any>;
      /**
       * Correlation ID for an error whose details were withheld. Present on
       * internal errors, where the full exception is written to the server log
       * under this same ID — surface it so a user can quote it to support.
       */
      #{formatted_error_id_field()}?: string;
    }

    /**
     * Represents the result of a validation RPC call.
     *
     * All validation actions return this same structure, indicating either
     * successful validation or a list of validation errors.
     *
     * @example
     * // Successful validation
     * const result: ValidationResult = { #{formatted_success_field()}: true };
     *
     * // Failed validation
     * const result: ValidationResult = {
     *   #{formatted_success_field()}: false,
     *   #{formatted_errors_field()}: [
     *     {
     *       #{formatted_error_type_field()}: "required",
     *       #{formatted_error_message_field()}: "is required",
     *       #{formatted_error_short_message_field()}: "Required field",
     *       #{formatted_error_vars_field()}: { field: "email" },
     *       #{formatted_error_fields_field()}: ["email"],
     *       #{formatted_error_path_field()}: []
     *     }
     *   ]
     * };
     */
    export type ValidationResult =
      | { #{formatted_success_field()}: true }
      | { #{formatted_success_field()}: false; #{formatted_errors_field()}: AshRpcError[]; };



    """
  end
end
