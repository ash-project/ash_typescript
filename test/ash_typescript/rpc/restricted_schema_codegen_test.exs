# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# A recursive resource held by a struct attribute (defined at top level so
# Spark compiles it before the inline domain references it).
defmodule AshTypescript.Rpc.RestrictedSchemaCodegenTest.RNode do
  @moduledoc false
  use Ash.Resource, domain: nil, extensions: [AshTypescript.Resource]

  typescript do
    type_name "RestrictedRNode"
  end

  attributes do
    uuid_primary_key :id, public?: true
    attribute :label, :string, public?: true
    attribute :next, :struct, public?: true, constraints: [instance_of: __MODULE__]
  end

  calculations do
    calculate :shout, :string, expr(label), public?: true
  end
end

defmodule AshTypescript.Rpc.RestrictedSchemaCodegenTest.RTree do
  @moduledoc false
  use Ash.Resource,
    domain: AshTypescript.Rpc.RestrictedSchemaCodegenTest.RDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "RestrictedRTree"
  end

  attributes do
    uuid_primary_key :id

    attribute :root, :struct,
      public?: true,
      constraints: [instance_of: AshTypescript.Rpc.RestrictedSchemaCodegenTest.RNode]
  end

  actions do
    defaults [:read]
  end
end

defmodule AshTypescript.Rpc.RestrictedSchemaCodegenTest.RDomain do
  @moduledoc false
  use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource AshTypescript.Rpc.RestrictedSchemaCodegenTest.RTree do
      rpc_action :list_r_trees, :read, allowed_loads: []
    end
  end

  resources do
    resource AshTypescript.Rpc.RestrictedSchemaCodegenTest.RTree
  end
end

defmodule AshTypescript.Rpc.RestrictedSchemaCodegenTest do
  use ExUnit.Case

  @moduletag :ash_typescript

  # Snapshot the global config this module mutates so it cannot leak into
  # later test modules.
  setup_all do
    AshTypescript.Test.TestHelpers.restore_application_env_on_exit([:enable_namespace_files])
  end

  setup do
    Application.put_env(:ash_typescript, :enable_namespace_files, false)
    :ok
  end

  setup_all do
    {:ok, generated_typescript} =
      AshTypescript.Test.CodegenTestHelper.generate_all_content()

    %{generated: generated_typescript}
  end

  describe "denied_loads schema generation" do
    test "generates Omit schema for simple denied_loads", %{generated: generated} do
      assert generated =~
               ~r/type ListTodosDenyUserSchema = Omit<TodoResourceSchema, '__primitiveFields' \| 'user'>/
    end

    test "uses restricted schema in Fields type", %{generated: generated} do
      assert generated =~
               ~r/ListTodosDenyUserFields = UnifiedFieldSelection<ListTodosDenyUserSchema>/
    end

    test "uses restricted schema in InferResult", %{generated: generated} do
      assert generated =~ ~r/InferResult<ListTodosDenyUserSchema, Fields>/
    end

    test "keeps nullability of a restricted array of embedded resources", %{
      generated: generated
    } do
      assert generated =~
               "metadataHistory: { __type: \"Relationship\"; __array: true; " <>
                 "__resource: ListTodosDenyHistoryCalcSchemaMetadataHistory | null; }"
    end
  end

  describe "allowed_loads schema generation" do
    test "generates Omit schema and overrides allowed fields with AttributesOnlySchema", %{
      generated: generated
    } do
      assert generated =~ ~r/type ListTodosAllowOnlyUserSchema = Omit<TodoResourceSchema,/

      assert generated =~
               ~r/type ListTodosAllowOnlyUserSchema = Omit<TodoResourceSchema, [^>]*'comments'/

      assert generated =~
               ~r/type ListTodosAllowOnlyUserSchema = Omit<TodoResourceSchema, [^>]*'user'/

      assert generated =~
               ~r/user: \{ __type: "Relationship"; __resource: UserAttributesOnlySchema/
    end

    test "uses restricted schema in Fields type", %{generated: generated} do
      assert generated =~
               ~r/ListTodosAllowOnlyUserFields = UnifiedFieldSelection<ListTodosAllowOnlyUserSchema>/
    end
  end

  describe "nested denied_loads schema generation" do
    test "generates nested restricted schema for denied_loads: [comments: [:todo]]", %{
      generated: generated
    } do
      assert generated =~
               ~r/type ListTodosDenyNestedSchemaComments = Omit<TodoCommentResourceSchema, '__primitiveFields' \| 'todo'>/
    end

    test "generates main schema that overrides comments relationship", %{generated: generated} do
      assert generated =~
               ~r/type ListTodosDenyNestedSchema = Omit<TodoResourceSchema, '__primitiveFields' \| 'comments'> & \{/

      assert generated =~
               ~r/comments: \{ __type: "Relationship"; __array: true; __resource: ListTodosDenyNestedSchemaComments; /
    end
  end

  describe "nested allowed_loads schema generation" do
    test "generates nested restricted schema for allowed_loads: [:user, comments: [:todo]]", %{
      generated: generated
    } do
      assert generated =~
               ~r/type ListTodosAllowNestedSchemaComments = Omit<TodoCommentResourceSchema,/

      assert generated =~
               ~r/type ListTodosAllowNestedSchemaComments = Omit<TodoCommentResourceSchema, [^>]*'todo'/

      assert generated =~
               ~r/todo: \{ __type: "Relationship"; __resource: \(Omit<TodoAttributesOnlySchema, /
    end

    test "generates main schema with user and comments using appropriate schemas", %{
      generated: generated
    } do
      assert generated =~ ~r/type ListTodosAllowNestedSchema = Omit<TodoResourceSchema,/

      assert generated =~
               ~r/type ListTodosAllowNestedSchema = Omit<TodoResourceSchema, [^>]*'user'/

      assert generated =~
               ~r/user: \{ __type: "Relationship"; __resource: UserAttributesOnlySchema/
    end
  end

  describe "scalar loads (calculations and aggregates)" do
    test "an allowed scalar calculation is not omitted", %{generated: generated} do
      # allowed_loads: [comments: [:weighted_score]]
      assert generated =~
               ~r/type ListTodosAllowNestedCalcSchemaComments = Omit<TodoCommentResourceSchema, [^>]*'todo'/

      refute generated =~
               ~r/type ListTodosAllowNestedCalcSchemaComments = Omit<TodoCommentResourceSchema, [^>]*'weightedScore'/
    end

    test "restricted schemas rewrite __primitiveFields so scalar loads are actually restricted",
         %{generated: generated} do
      # Omit cannot reach the leaf-name union: LeafFieldSelection<T> = T["__primitiveFields"]
      assert generated =~
               ~r/type ListTodosDenyNestedCalcSchemaComments = Omit<TodoCommentResourceSchema, '__primitiveFields' \| 'weightedScore'> & \{\n\s*__primitiveFields: Exclude<TodoCommentResourceSchema\["__primitiveFields"\], 'weightedScore'>;/
    end

    test "omit keys use the resource-aware field name mapping", %{generated: generated} do
      # User maps is_active? -> "isActive"; 'isActive?' would be a silent no-op
      assert generated =~
               ~r/type ListUsersDenyMappedCalcSchema = Omit<UserResourceSchema, '__primitiveFields' \| 'isActive'>/

      assert generated =~
               ~r/type ListTodosDenyMappedCalcSchemaUser = Omit<UserResourceSchema, '__primitiveFields' \| 'isActive'>/

      refute generated =~ ~r/'isActive\?'/
    end
  end

  describe "restrictions through an embedded resource" do
    test "a nested deny overrides the embedded attribute with a nested schema omitting the field",
         %{generated: generated} do
      # denied_loads: [metadata: [:display_category]]
      assert generated =~
               "metadata: { __type: \"Relationship\"; " <>
                 "__resource: ListTodosDenyEmbeddedSchemaMetadata | null; }"

      assert generated =~
               "type ListTodosDenyEmbeddedSchemaMetadata = " <>
                 "Omit<TodoMetadataResourceSchema, '__primitiveFields' | 'displayCategory'> & {\n" <>
                 "  __primitiveFields: Exclude<TodoMetadataResourceSchema[\"__primitiveFields\"], " <>
                 "'displayCategory'>;\n};"

      assert generated =~
               ~r/type ListTodosDenyEmbeddedSchema = Omit<TodoResourceSchema, '__primitiveFields' \| 'metadata'>/
    end

    test "a nested allow keeps only the allowed loadable of the embedded resource",
         %{generated: generated} do
      # allowed_loads: [metadata: [:display_category]]
      assert generated =~
               "metadata: { __type: \"Relationship\"; " <>
                 "__resource: ListTodosAllowEmbeddedSchemaMetadata | null; }"

      [nested] =
        Regex.run(~r/type ListTodosAllowEmbeddedSchemaMetadata = Omit<[^>]*>/, generated)

      for omitted <- ["'adjustedPriority'", "'isOverdue'", "'formattedSummary'"] do
        assert nested =~ omitted
      end

      refute nested =~ "'displayCategory'"
    end

    test "a flat allow overrides the embedded attribute with its AttributesOnlySchema",
         %{generated: generated} do
      # allowed_loads: [:metadata]
      [schema] =
        Regex.run(~r/type ListTodosAllowFlatEmbeddedSchema = [^;]*;[^}]*\};/s, generated)

      assert schema =~
               "metadata: { __type: \"Relationship\"; " <>
                 "__resource: TodoMetadataAttributesOnlySchema | null; }"

      assert schema =~ ~r/Omit<TodoResourceSchema, [^>]*'metadata'/
    end

    test "a nested allow through an array of embedded resources keeps __array",
         %{generated: generated} do
      # allowed_loads: [metadata_history: [:display_category]]
      assert generated =~
               "metadataHistory: { __type: \"Relationship\"; __array: true; " <>
                 "__resource: ListTodosAllowHistorySchemaMetadataHistory | null; }"

      [nested] =
        Regex.run(~r/type ListTodosAllowHistorySchemaMetadataHistory = Omit<[^>]*>/, generated)

      assert nested =~ "'isOverdue'"
      refute nested =~ "'displayCategory'"
    end
  end

  describe "restrictions through union members" do
    test "a denied member field is replaced, other members kept", %{generated: generated} do
      # denied_loads: [content: [text: [:display_text]]]
      assert generated =~
               ~s(  content: { __type: "Union"; __primitiveFields: "note" | "priorityValue"; ) <>
                 "text?: ListTodosDenyUnionMemberSchemaContentText; " <>
                 "checklist?: TodoContentChecklistResourceSchema; " <>
                 "link?: AshTypescriptTestTodoContentLinkContentResourceSchema; " <>
                 "note?: string; priorityValue?: number; } | null;\n"

      assert generated =~
               "type ListTodosDenyUnionMemberSchemaContentText = " <>
                 "Omit<AshTypescriptTestTodoContentTextContentResourceSchema, " <>
                 "'__primitiveFields' | 'displayText'> & {\n"

      assert generated =~
               "type ListTodosDenyUnionMemberSchema = " <>
                 "Omit<TodoResourceSchema, '__primitiveFields' | 'content'> & {\n"
    end

    test "an allowed member field is the only loadable", %{generated: generated} do
      # allowed_loads: [content: [text: [:display_text]]]
      [nested] =
        Regex.run(
          ~r/type ListTodosAllowUnionMemberSchemaContentText = Omit<[^>]*>/,
          generated
        )

      assert nested =~ "'isFormatted'"
      refute nested =~ "'displayText'"

      # Members the entry doesn't name keep their attributes only.
      assert generated =~
               ~s(  content: { __type: "Union"; __primitiveFields: "note" | "priorityValue"; ) <>
                 "text?: ListTodosAllowUnionMemberSchemaContentText; " <>
                 "checklist?: TodoContentChecklistAttributesOnlySchema; " <>
                 "link?: AshTypescriptTestTodoContentLinkContentAttributesOnlySchema; " <>
                 "note?: string; priorityValue?: number; } | null;\n"
    end

    test "an array of unions keeps __array", %{generated: generated} do
      # denied_loads: [blocks: [text: [:display_text]]]
      assert generated =~
               ~r/  blocks: \{ __array: true; +__type: "Union"; __primitiveFields: "note"; text\?: ListTodosDenyBlockMemberSchemaBlocksText; note\?: string; +\} \| null;\n/
    end

    test "no restricted schema uses __members", %{generated: generated} do
      refute generated =~ "__members"
    end
  end

  describe "a restriction through a calculation returning a resource" do
    test "keeps the calculation's arguments", %{generated: generated} do
      # denied_loads: [self: [:user]]
      assert generated =~
               ~s(  self: { __type: "ComplexCalculation"; ) <>
                 "__returnType: ListTodosDenySelfUserSchemaSelf | null; " <>
                 "__args: { prefix?: string | null; count?: number | null; " <>
                 "enabled?: boolean | null; data?: Record<string, any> | null }; };\n"

      assert generated =~
               "type ListTodosDenySelfUserSchemaSelf = " <>
                 "Omit<TodoResourceSchema, '__primitiveFields' | 'user'> & {\n"
    end
  end

  describe "a restriction through an aggregate holding an embedded resource" do
    test "the nested schema restricts the aggregate's attributes-only schema",
         %{generated: generated} do
      # denied_loads: [first_comment_metadata: [:display_category]]
      assert generated =~
               ~s(  firstCommentMetadata: { __type: "Relationship"; ) <>
                 "__resource: ListTodosDenyAggregateEmbeddedSchemaFirstCommentMetadata | null; };\n"

      assert generated =~
               "type ListTodosDenyAggregateEmbeddedSchemaFirstCommentMetadata = " <>
                 "Omit<TodoMetadataAttributesOnlySchema, '__primitiveFields' | 'displayCategory'> & {\n"
    end
  end

  # Load restrictions restrict loads only (relationships, calculations,
  # aggregates); ash_rpc never restricts attributes.
  describe "bare denied attributes and members keep their attributes" do
    setup %{generated: generated} do
      [schema] =
        Regex.run(~r/type ListTodosDenyBareFieldsSchema = .*?\n\};/s, generated)

      %{schema: schema}
    end

    test "an embedded attribute gets its AttributesOnlySchema", %{schema: schema} do
      # denied_loads: [:metadata]
      assert schema =~
               "  metadata: { __type: \"Relationship\"; " <>
                 "__resource: TodoMetadataAttributesOnlySchema | null; };\n"
    end

    test "a union attribute keeps its members, resource members' attributes only",
         %{schema: schema} do
      # denied_loads: [:blocks]
      assert schema =~
               ~r/  blocks: \{ __array: true; +__type: "Union"; __primitiveFields: "note"; text\?: AshTypescriptTestTodoContentTextContentAttributesOnlySchema; note\?: string; +\} \| null;\n/
    end

    test "bare members keep their attributes, scalar members unchanged", %{schema: schema} do
      # denied_loads: [content: [:text, :note]]
      assert schema =~
               ~s(  content: { __type: "Union"; __primitiveFields: "note" | "priorityValue"; ) <>
                 "text?: AshTypescriptTestTodoContentTextContentAttributesOnlySchema; " <>
                 "checklist?: TodoContentChecklistResourceSchema; " <>
                 "link?: AshTypescriptTestTodoContentLinkContentResourceSchema; " <>
                 "note?: string; priorityValue?: number; } | null;\n"
    end

    test "the fields are replaced, not removed", %{schema: schema} do
      assert schema =~
               ~r/Omit<TodoResourceSchema, '__primitiveFields' \| 'metadata' \| 'blocks' \| 'content'>/
    end
  end

  describe "allowed_loads gives unnamed embedded and union attributes their attributes only" do
    setup %{generated: generated} do
      [schema] =
        Regex.run(~r/type ListTodosAllowOnlyUserSchema = .*?\n\};/s, generated)

      [comments] =
        Regex.run(~r/type ListTodosAllowNestedSchemaComments = .*?\n\};/s, generated)

      %{schema: schema, comments: comments}
    end

    test "an embedded attribute and an array of one", %{schema: schema} do
      assert schema =~
               "  metadata: { __type: \"Relationship\"; " <>
                 "__resource: TodoMetadataAttributesOnlySchema | null; };\n"

      assert schema =~
               "  metadataHistory: { __type: \"Relationship\"; __array: true; " <>
                 "__resource: TodoMetadataAttributesOnlySchema | null; };\n"
    end

    test "a union attribute's resource members", %{schema: schema} do
      assert schema =~
               ~s(  content: { __type: "Union"; __primitiveFields: "note" | "priorityValue"; ) <>
                 "text?: AshTypescriptTestTodoContentTextContentAttributesOnlySchema; " <>
                 "checklist?: TodoContentChecklistAttributesOnlySchema; " <>
                 "link?: AshTypescriptTestTodoContentLinkContentAttributesOnlySchema; " <>
                 "note?: string; priorityValue?: number; } | null;\n"

      assert schema =~
               ~r/  blocks: \{ __array: true; +__type: "Union"; __primitiveFields: "note"; text\?: AshTypescriptTestTodoContentTextContentAttributesOnlySchema; note\?: string; +\} \| null;\n/
    end

    test "a union without resource members keeps its type", %{schema: schema} do
      refute schema =~ "statusInfo:"
      refute schema =~ "attachments:"
    end

    test "a named attribute keeps its one override", %{generated: generated} do
      # allowed_loads: [metadata: [:display_category]]
      [schema] =
        Regex.run(~r/type ListTodosAllowEmbeddedSchema = .*?\n\};/s, generated)

      assert [_one] = Regex.scan(~r/\n  metadata: /, schema)
      assert schema =~ "__resource: ListTodosAllowEmbeddedSchemaMetadata | null; };\n"
    end

    test "in a nested allow too", %{comments: comments} do
      assert comments =~
               ~s(  authorInfo: { __type: "Union"; __primitiveFields: "anonymous"; ) <>
                 "metadata?: TodoMetadataAttributesOnlySchema; anonymous?: string; } | null;\n"

      assert comments =~
               "  commentMetadata: { __type: \"Relationship\"; " <>
                 "__resource: TodoMetadataAttributesOnlySchema | null; };\n"
    end
  end

  # A resource typed with its attributes only (a flat allowed relationship) has
  # no loads anywhere under it: its union attributes' resource members (which
  # the base AttributesOnlySchema types in full) get their attributes only too.
  describe "attributes only, all the way down" do
    test "a flat allowed relationship's union attributes", %{generated: generated} do
      # allowed_loads: [:user, comments: [:todo]]
      [comments] =
        Regex.run(~r/type ListTodosAllowNestedSchemaComments = .*?\n\};/s, generated)

      [todo] = Regex.run(~r/\n  todo: [^\n]*\n/, comments)

      assert todo =~
               ~s(  todo: { __type: "Relationship"; __resource: ) <>
                 "(Omit<TodoAttributesOnlySchema, 'blocks' | 'content'> & { blocks: "

      assert todo =~
               ~s(content: { __type: "Union"; __primitiveFields: "note" | "priorityValue"; ) <>
                 "text?: AshTypescriptTestTodoContentTextContentAttributesOnlySchema; " <>
                 "checklist?: TodoContentChecklistAttributesOnlySchema; "

      refute todo =~ "ResourceSchema"
    end

    test "unrestricted schemas keep the base AttributesOnlySchema", %{generated: generated} do
      assert generated =~
               ~s(  content: { __type: "Union"; __primitiveFields: "note" | "priorityValue"; ) <>
                 "text?: AshTypescriptTestTodoContentTextContentResourceSchema; "

      assert generated =~
               ~s(  firstCommentMetadata: { __type: "Relationship"; ) <>
                 "__resource: TodoMetadataAttributesOnlySchema | null; };\n"
    end

    test "a resource without such attributes keeps its AttributesOnlySchema name",
         %{generated: generated} do
      assert generated =~
               ~r/type ListTodosAllowOnlyUserSchema = .*?\n  user: \{ __type: "Relationship"; __resource: UserAttributesOnlySchema; \};/s
    end
  end

  describe "restricted has_many / many_to_many keep the query markers" do
    test "a nested deny", %{generated: generated} do
      # denied_loads: [comments: [:todo]]
      assert generated =~
               "  comments: { __type: \"Relationship\"; __array: true; " <>
                 "__resource: ListTodosDenyNestedSchemaComments; __pagination: \"mixed\"; " <>
                 "__filterInput: TodoCommentFilterInput; __sortField: TodoCommentSortField; };\n"
    end

    test "a nested allow", %{generated: generated} do
      # allowed_loads: [:user, comments: [:todo]]
      assert generated =~
               "  comments: { __type: \"Relationship\"; __array: true; " <>
                 "__resource: ListTodosAllowNestedSchemaComments; __pagination: \"mixed\"; " <>
                 "__filterInput: TodoCommentFilterInput; __sortField: TodoCommentSortField; };\n"
    end
  end

  defmodule QChild do
    @moduledoc false
    use Ash.Resource,
      domain: AshTypescript.Rpc.RestrictedSchemaCodegenTest.QDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "RestrictedQChild"
    end

    attributes do
      uuid_primary_key :id
      attribute :parent_id, :uuid, public?: true
      attribute :label, :string, public?: true
    end

    actions do
      defaults [:read]
    end
  end

  defmodule QParent do
    @moduledoc false
    use Ash.Resource,
      domain: AshTypescript.Rpc.RestrictedSchemaCodegenTest.QDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "RestrictedQParent"
      field_names best_children?: "bestChildren"
    end

    attributes do
      uuid_primary_key :id
    end

    relationships do
      has_many :best_children?, AshTypescript.Rpc.RestrictedSchemaCodegenTest.QChild do
        public? true
        destination_attribute :parent_id
      end
    end

    actions do
      defaults [:read]
    end
  end

  defmodule QDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource AshTypescript.Rpc.RestrictedSchemaCodegenTest.QParent do
        rpc_action :list_q_parents, :read, denied_loads: [best_children?: [:label]]
      end

      resource AshTypescript.Rpc.RestrictedSchemaCodegenTest.QChild
    end

    resources do
      resource AshTypescript.Rpc.RestrictedSchemaCodegenTest.QParent
      resource AshTypescript.Rpc.RestrictedSchemaCodegenTest.QChild
    end
  end

  defmodule StepDomain do
    @moduledoc false
    use Ash.Domain,
      otp_app: :ash_typescript,
      validate_config_inclusion?: false,
      extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource AshTypescript.Test.Todo do
        rpc_action :step_unexposed_relationship, :read, denied_loads: [not_exposed_items: []]
        rpc_action :step_resource_calculation, :read, denied_loads: [self: [:user]]
        rpc_action :step_flat_union_aggregate, :read, allowed_loads: [:first_comment_author_info]
        rpc_action :step_flat_resource_calculation, :read, allowed_loads: [:self]
        rpc_action :step_flat_union, :read, allowed_loads: [:content]
        rpc_action :step_bare_member_deny, :read, denied_loads: [content: [:text, :note]]
        rpc_action :step_bare_member_allow, :read, allowed_loads: [content: [:text]]
        rpc_action :step_flat_has_many, :read, allowed_loads: [:comments]
        rpc_action :step_empty_allow, :read, allowed_loads: []
        rpc_action :step_bare_union_calculation, :read, denied_loads: [:first_comment_author_info]
      end
    end

    resources do
    end
  end

  describe "each load-path step" do
    setup do
      manifest =
        AshTypescript.Test.InlineManifest.build!(domains: [AshTypescript.Test.Domain, StepDomain])

      schema = fn rpc_name ->
        AshTypescript.with_manifest(manifest, fn ->
          {schema_def, _name} =
            AshTypescript.Rpc.Codegen.TypeGenerators.RestrictedSchema.get_schema_and_reference(
              AshTypescript.Test.Todo,
              %{name: rpc_name},
              AshRpc.Manifest.resource_lookup(manifest)
            )

          schema_def
        end)
      end

      %{schema: schema}
    end

    test "a relationship to an unexposed resource gets no override", %{schema: schema} do
      schema_def = schema.(:step_unexposed_relationship)

      refute schema_def =~ "notExposedItems:"
      refute schema_def =~ "NotExposed"
    end

    test "a calculation returning a resource gets a nested schema", %{schema: schema} do
      assert schema.(:step_resource_calculation) =~
               "type StepResourceCalculationSchemaSelf = " <>
                 "Omit<TodoResourceSchema, '__primitiveFields' | 'user'>"
    end

    test "a flat allowed union aggregate keeps its resource members' attributes only",
         %{schema: schema} do
      assert schema.(:step_flat_union_aggregate) =~
               ~s(  firstCommentAuthorInfo: { __type: "Union"; __primitiveFields: "anonymous"; ) <>
                 "metadata?: TodoMetadataAttributesOnlySchema; anonymous?: string; } | null;\n"
    end

    test "a flat allowed calculation returning a resource keeps its arguments",
         %{schema: schema} do
      assert schema.(:step_flat_resource_calculation) =~
               ~r/  self: \{ __type: "ComplexCalculation"; __returnType: \(Omit<TodoAttributesOnlySchema, 'blocks' \| 'content'> & \{ [^\n]* \| null; __args: \{ prefix\?: string \| null; /
    end

    test "a flat allowed union attribute keeps its resource members' attributes only",
         %{schema: schema} do
      schema_def = schema.(:step_flat_union)

      assert schema_def =~
               "text?: AshTypescriptTestTodoContentTextContentAttributesOnlySchema; " <>
                 "checklist?: TodoContentChecklistAttributesOnlySchema; "

      assert schema_def =~ ~r/Omit<TodoResourceSchema, [^>]*'content'/
    end

    test "a bare member in denied_loads keeps its attributes only", %{schema: schema} do
      assert schema.(:step_bare_member_deny) =~
               ~s(  content: { __type: "Union"; __primitiveFields: "note" | "priorityValue"; ) <>
                 "text?: AshTypescriptTestTodoContentTextContentAttributesOnlySchema; " <>
                 "checklist?: TodoContentChecklistResourceSchema; " <>
                 "link?: AshTypescriptTestTodoContentLinkContentResourceSchema; " <>
                 "note?: string; priorityValue?: number; } | null;\n"
    end

    test "a bare denied union aggregate is a load, so it is removed", %{schema: schema} do
      schema_def = schema.(:step_bare_union_calculation)

      assert schema_def =~
               ~r/Omit<TodoResourceSchema, '__primitiveFields' \| 'firstCommentAuthorInfo'>/

      refute schema_def =~ "firstCommentAuthorInfo:"
    end

    test "a flat allowed has_many keeps the query markers", %{schema: schema} do
      assert schema.(:step_flat_has_many) =~
               ~r/  comments: \{ __type: "Relationship"; __array: true; __resource: [^\n]*; __pagination: "mixed"; __filterInput: TodoCommentFilterInput; __sortField: TodoCommentSortField; \};\n/
    end

    test "a flat allowed has_many's union members keep their attributes only",
         %{schema: schema} do
      assert schema.(:step_flat_has_many) =~
               "__resource: (Omit<TodoCommentAttributesOnlySchema, 'authorInfo'> & " <>
                 ~s({ authorInfo: { __type: "Union"; __primitiveFields: "anonymous"; ) <>
                 "metadata?: TodoMetadataAttributesOnlySchema; anonymous?: string; } | null; });"
    end

    test "an empty allow list keeps embedded attributes' attributes only", %{schema: schema} do
      assert schema.(:step_empty_allow) =~
               "  metadata: { __type: \"Relationship\"; " <>
                 "__resource: TodoMetadataAttributesOnlySchema | null; };\n"
    end

    test "a bare member in allowed_loads keeps its attributes only", %{schema: schema} do
      assert schema.(:step_bare_member_allow) =~
               "text?: AshTypescriptTestTodoContentTextContentAttributesOnlySchema; " <>
                 "checklist?: TodoContentChecklistAttributesOnlySchema; "
    end
  end

  describe "a recursive resource held by an attribute" do
    test "its attributes-only type stops at a resource it is already in" do
      manifest =
        AshTypescript.Test.InlineManifest.build!(
          domains: [AshTypescript.Rpc.RestrictedSchemaCodegenTest.RDomain],
          body: nil
        )

      {schema_def, "ListRTreesSchema"} =
        AshTypescript.with_manifest(manifest, fn ->
          AshTypescript.Rpc.Codegen.TypeGenerators.RestrictedSchema.get_schema_and_reference(
            AshTypescript.Rpc.RestrictedSchemaCodegenTest.RTree,
            %{name: :list_r_trees},
            AshRpc.Manifest.resource_lookup(manifest)
          )
        end)

      assert schema_def =~
               ~s(  root: { __type: "Relationship"; ) <>
                 "__resource: RestrictedRNodeAttributesOnlySchema | null; };\n"
    end
  end

  describe "nested schema names" do
    test "a nested schema name built from a raw name with ? is an identifier" do
      manifest = AshTypescript.Test.InlineManifest.build!(domains: [QDomain])

      {schema_def, "ListQParentsSchema"} =
        AshTypescript.with_manifest(manifest, fn ->
          AshTypescript.Rpc.Codegen.TypeGenerators.RestrictedSchema.get_schema_and_reference(
            QParent,
            %{name: :list_q_parents},
            AshRpc.Manifest.resource_lookup(manifest)
          )
        end)

      assert schema_def =~
               "type ListQParentsSchemaBestChildren = Omit<RestrictedQChildResourceSchema"

      assert schema_def =~ "__resource: ListQParentsSchemaBestChildren; __pagination: "
      refute schema_def =~ "?;"
      refute schema_def =~ "BestChildren?"
    end
  end

  describe "unrestricted actions" do
    test "use base resource schema when no restrictions", %{generated: generated} do
      assert generated =~ ~r/ListTodosFields = UnifiedFieldSelection<TodoResourceSchema>/
      refute generated =~ ~r/type ListTodosSchema = /
    end
  end

  describe "schema integration with InferResult" do
    test "restricted schema works with pagination types", %{generated: generated} do
      assert generated =~
               ~r/InferListTodosDenyUserResult<[^>]*Fields[^>]*Page[^>]*> = ConditionalPaginatedResultMixed<Page, Array<InferResult<ListTodosDenyUserSchema, Fields>>/
    end
  end
end
