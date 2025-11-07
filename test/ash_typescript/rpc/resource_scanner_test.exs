# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ResourceScannerTest do
  use ExUnit.Case, async: true

  alias AshTypescript.Rpc.ResourceScanner

  describe "scan_rpc_resources/1" do
    test "finds all Ash resources referenced by RPC resources" do
      all_resources = ResourceScanner.scan_rpc_resources(:ash_typescript)

      # Should find embedded resources like TodoMetadata
      assert AshTypescript.Test.TodoMetadata in all_resources

      # Should find content embedded resources
      assert AshTypescript.Test.TodoContent.TextContent in all_resources
      assert AshTypescript.Test.TodoContent.ChecklistContent in all_resources
      assert AshTypescript.Test.TodoContent.LinkContent in all_resources

      # Should be a list of unique resources
      assert length(all_resources) == length(Enum.uniq(all_resources))
    end

    test "finds resources referenced in calculations" do
      all_resources = ResourceScanner.scan_rpc_resources(:ash_typescript)

      # Todo has a :self calculation that returns Ash.Type.Struct with instance_of: Todo
      # So Todo should reference itself
      assert AshTypescript.Test.Todo in all_resources
    end

    test "finds resources in union types" do
      all_resources = ResourceScanner.scan_rpc_resources(:ash_typescript)

      # Todo has a :content union attribute with embedded resources
      assert AshTypescript.Test.TodoContent.TextContent in all_resources
      assert AshTypescript.Test.TodoContent.ChecklistContent in all_resources
      assert AshTypescript.Test.TodoContent.LinkContent in all_resources
    end

    test "finds resources in nested embedded resources" do
      all_resources = ResourceScanner.scan_rpc_resources(:ash_typescript)

      # If an embedded resource references another embedded resource,
      # both should be found
      # (based on the structure of the test resources)
      assert AshTypescript.Test.TodoMetadata in all_resources
    end
  end

  describe "get_rpc_resources/1" do
    test "returns all RPC resources configured in domains" do
      rpc_resources = ResourceScanner.get_rpc_resources(:ash_typescript)

      # These are configured in test/support/domain.ex
      assert AshTypescript.Test.Todo in rpc_resources
      assert AshTypescript.Test.TodoComment in rpc_resources
      assert AshTypescript.Test.User in rpc_resources
      assert AshTypescript.Test.UserSettings in rpc_resources
      assert AshTypescript.Test.OrgTodo in rpc_resources
      assert AshTypescript.Test.Task in rpc_resources

      # These are NOT configured as RPC resources
      refute AshTypescript.Test.TodoMetadata in rpc_resources
      refute AshTypescript.Test.NotExposed in rpc_resources
    end
  end

  describe "find_referenced_resources/1" do
    test "finds resources in attributes" do
      resources = ResourceScanner.find_referenced_resources(AshTypescript.Test.Todo)

      # Todo has :metadata attribute of type TodoMetadata (embedded resource)
      assert AshTypescript.Test.TodoMetadata in resources
    end

    test "finds resources in calculations" do
      resources = ResourceScanner.find_referenced_resources(AshTypescript.Test.Todo)

      # Todo has :self calculation that returns Ash.Type.Struct with instance_of: Todo
      assert AshTypescript.Test.Todo in resources
    end

    test "finds resources in union attributes" do
      resources = ResourceScanner.find_referenced_resources(AshTypescript.Test.Todo)

      # Todo has :content union with embedded resources
      assert AshTypescript.Test.TodoContent.TextContent in resources
      assert AshTypescript.Test.TodoContent.ChecklistContent in resources
      assert AshTypescript.Test.TodoContent.LinkContent in resources
    end

    test "finds resources in array attributes" do
      resources = ResourceScanner.find_referenced_resources(AshTypescript.Test.Todo)

      # Todo has :metadata_history attribute of type {:array, TodoMetadata}
      assert AshTypescript.Test.TodoMetadata in resources
    end
  end

  describe "traverse_type/2" do
    test "finds resource in direct module reference" do
      resources = ResourceScanner.traverse_type(AshTypescript.Test.TodoMetadata, [])

      assert AshTypescript.Test.TodoMetadata in resources
    end

    test "finds resource in Ash.Type.Struct with instance_of" do
      resources =
        ResourceScanner.traverse_type(Ash.Type.Struct,
          instance_of: AshTypescript.Test.TodoMetadata
        )

      assert AshTypescript.Test.TodoMetadata in resources
    end

    test "finds resources in Ash.Type.Union" do
      constraints = [
        types: [
          text: [
            type: AshTypescript.Test.TodoContent.TextContent,
            constraints: []
          ],
          checklist: [
            type: AshTypescript.Test.TodoContent.ChecklistContent,
            constraints: []
          ]
        ]
      ]

      resources = ResourceScanner.traverse_type(Ash.Type.Union, constraints)

      assert AshTypescript.Test.TodoContent.TextContent in resources
      assert AshTypescript.Test.TodoContent.ChecklistContent in resources
    end

    test "finds resources in array types" do
      resources =
        ResourceScanner.traverse_type({:array, AshTypescript.Test.TodoMetadata}, [])

      assert AshTypescript.Test.TodoMetadata in resources
    end

    test "finds resources in Map type with fields containing resources" do
      constraints = [
        fields: [
          user: [
            type: AshTypescript.Test.User,
            constraints: []
          ],
          metadata: [
            type: AshTypescript.Test.TodoMetadata,
            constraints: []
          ]
        ]
      ]

      resources = ResourceScanner.traverse_type(Ash.Type.Map, constraints)

      assert AshTypescript.Test.User in resources
      assert AshTypescript.Test.TodoMetadata in resources
    end

    test "finds resources in Keyword type with fields containing resources" do
      constraints = [
        fields: [
          user: [
            type: AshTypescript.Test.User,
            constraints: []
          ]
        ]
      ]

      resources = ResourceScanner.traverse_type(Ash.Type.Keyword, constraints)

      assert AshTypescript.Test.User in resources
    end

    test "finds resources in Tuple type with fields containing resources" do
      constraints = [
        fields: [
          first: [
            type: AshTypescript.Test.User,
            constraints: []
          ]
        ]
      ]

      resources = ResourceScanner.traverse_type(Ash.Type.Tuple, constraints)

      assert AshTypescript.Test.User in resources
    end

    test "handles nested structures" do
      # Map containing a union with resources
      constraints = [
        fields: [
          content: [
            type: Ash.Type.Union,
            constraints: [
              types: [
                text: [
                  type: AshTypescript.Test.TodoContent.TextContent,
                  constraints: []
                ]
              ]
            ]
          ]
        ]
      ]

      resources = ResourceScanner.traverse_type(Ash.Type.Map, constraints)

      assert AshTypescript.Test.TodoContent.TextContent in resources
    end

    test "returns empty list for primitive types" do
      assert ResourceScanner.traverse_type(Ash.Type.String, []) == []
      assert ResourceScanner.traverse_type(Ash.Type.Integer, []) == []
      assert ResourceScanner.traverse_type(Ash.Type.Boolean, []) == []
      assert ResourceScanner.traverse_type(:string, []) == []
      assert ResourceScanner.traverse_type(:integer, []) == []
    end

    test "returns empty list for Map without fields" do
      assert ResourceScanner.traverse_type(Ash.Type.Map, []) == []
    end

    test "returns empty list for Union without types" do
      assert ResourceScanner.traverse_type(Ash.Type.Union, []) == []
    end

    test "returns empty list for Struct without instance_of" do
      assert ResourceScanner.traverse_type(Ash.Type.Struct, []) == []
    end
  end

  describe "traverse_fields/1" do
    test "finds resources in field definitions" do
      fields = [
        user: [
          type: AshTypescript.Test.User,
          constraints: []
        ],
        metadata: [
          type: AshTypescript.Test.TodoMetadata,
          constraints: []
        ],
        name: [
          type: :string,
          constraints: []
        ]
      ]

      resources = ResourceScanner.traverse_fields(fields)

      assert AshTypescript.Test.User in resources
      assert AshTypescript.Test.TodoMetadata in resources
    end

    test "handles fields with nested structures" do
      fields = [
        data: [
          type: Ash.Type.Struct,
          constraints: [instance_of: AshTypescript.Test.TodoMetadata]
        ]
      ]

      resources = ResourceScanner.traverse_fields(fields)

      assert AshTypescript.Test.TodoMetadata in resources
    end

    test "returns empty list for invalid input" do
      assert ResourceScanner.traverse_fields(nil) == []
      assert ResourceScanner.traverse_fields("invalid") == []
      assert ResourceScanner.traverse_fields(%{}) == []
    end

    test "returns empty list for fields with no type" do
      fields = [
        invalid_field: [
          constraints: []
        ]
      ]

      assert ResourceScanner.traverse_fields(fields) == []
    end
  end

  describe "integration: filtering results" do
    test "can filter for non-RPC resources" do
      all_resources = ResourceScanner.scan_rpc_resources(:ash_typescript)
      rpc_resources = ResourceScanner.get_rpc_resources(:ash_typescript)

      non_rpc = Enum.reject(all_resources, &(&1 in rpc_resources))

      # Should include embedded resources
      assert AshTypescript.Test.TodoMetadata in non_rpc

      # Should not include RPC resources
      refute AshTypescript.Test.Todo in non_rpc
      refute AshTypescript.Test.User in non_rpc
    end

    test "can filter for embedded resources only" do
      all_resources = ResourceScanner.scan_rpc_resources(:ash_typescript)

      embedded = Enum.filter(all_resources, &Ash.Resource.Info.embedded?/1)

      # Should include embedded resources
      assert AshTypescript.Test.TodoMetadata in embedded
      assert AshTypescript.Test.TodoContent.TextContent in embedded

      # Should not include non-embedded resources
      refute AshTypescript.Test.Todo in embedded
      refute AshTypescript.Test.User in embedded
    end

    test "can filter for non-embedded, non-RPC resources" do
      all_resources = ResourceScanner.scan_rpc_resources(:ash_typescript)
      rpc_resources = ResourceScanner.get_rpc_resources(:ash_typescript)

      non_rpc_non_embedded =
        all_resources
        |> Enum.reject(&(&1 in rpc_resources or Ash.Resource.Info.embedded?(&1)))

      # This should be empty in our test setup, or contain regular resources
      # that are referenced but not exposed as RPC
      assert is_list(non_rpc_non_embedded)
    end
  end
end
