# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.TypeDiscoveryTest do
  use ExUnit.Case, async: true

  alias AshTypescript.Codegen.TypeDiscovery

  describe "scan_rpc_resources/1" do
    test "finds all Ash resources referenced by RPC resources" do
      all_resources = TypeDiscovery.scan_rpc_resources(:ash_typescript)

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
      all_resources = TypeDiscovery.scan_rpc_resources(:ash_typescript)

      # Todo has a :self calculation that returns Ash.Type.Struct with instance_of: Todo
      # So Todo should reference itself
      assert AshTypescript.Test.Todo in all_resources
    end

    test "finds resources in union types" do
      all_resources = TypeDiscovery.scan_rpc_resources(:ash_typescript)

      # Todo has a :content union attribute with embedded resources
      assert AshTypescript.Test.TodoContent.TextContent in all_resources
      assert AshTypescript.Test.TodoContent.ChecklistContent in all_resources
      assert AshTypescript.Test.TodoContent.LinkContent in all_resources
    end

    test "finds resources in nested embedded resources" do
      all_resources = TypeDiscovery.scan_rpc_resources(:ash_typescript)

      # If an embedded resource references another embedded resource,
      # both should be found
      # (based on the structure of the test resources)
      assert AshTypescript.Test.TodoMetadata in all_resources
    end
  end

  describe "get_rpc_resources/1" do
    test "returns all RPC resources configured in domains" do
      rpc_resources = TypeDiscovery.get_rpc_resources(:ash_typescript)

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
      resources = TypeDiscovery.find_referenced_resources(AshTypescript.Test.Todo)

      # Todo has :metadata attribute of type TodoMetadata (embedded resource)
      assert AshTypescript.Test.TodoMetadata in resources
    end

    test "finds resources in calculations" do
      resources = TypeDiscovery.find_referenced_resources(AshTypescript.Test.Todo)

      # Todo has :self calculation that returns Ash.Type.Struct with instance_of: Todo
      assert AshTypescript.Test.Todo in resources
    end

    test "finds resources in union attributes" do
      resources = TypeDiscovery.find_referenced_resources(AshTypescript.Test.Todo)

      # Todo has :content union with embedded resources
      assert AshTypescript.Test.TodoContent.TextContent in resources
      assert AshTypescript.Test.TodoContent.ChecklistContent in resources
      assert AshTypescript.Test.TodoContent.LinkContent in resources
    end

    test "finds resources in array attributes" do
      resources = TypeDiscovery.find_referenced_resources(AshTypescript.Test.Todo)

      # Todo has :metadata_history attribute of type {:array, TodoMetadata}
      assert AshTypescript.Test.TodoMetadata in resources
    end
  end

  describe "traverse_type/2" do
    test "finds resource in direct module reference" do
      resources = TypeDiscovery.traverse_type(AshTypescript.Test.TodoMetadata, [])

      assert AshTypescript.Test.TodoMetadata in resources
    end

    test "finds resource in Ash.Type.Struct with instance_of" do
      resources =
        TypeDiscovery.traverse_type(Ash.Type.Struct,
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

      resources = TypeDiscovery.traverse_type(Ash.Type.Union, constraints)

      assert AshTypescript.Test.TodoContent.TextContent in resources
      assert AshTypescript.Test.TodoContent.ChecklistContent in resources
    end

    test "finds resources in array types" do
      resources =
        TypeDiscovery.traverse_type({:array, AshTypescript.Test.TodoMetadata}, [])

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

      resources = TypeDiscovery.traverse_type(Ash.Type.Map, constraints)

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

      resources = TypeDiscovery.traverse_type(Ash.Type.Keyword, constraints)

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

      resources = TypeDiscovery.traverse_type(Ash.Type.Tuple, constraints)

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

      resources = TypeDiscovery.traverse_type(Ash.Type.Map, constraints)

      assert AshTypescript.Test.TodoContent.TextContent in resources
    end

    test "returns empty list for primitive types" do
      assert TypeDiscovery.traverse_type(Ash.Type.String, []) == []
      assert TypeDiscovery.traverse_type(Ash.Type.Integer, []) == []
      assert TypeDiscovery.traverse_type(Ash.Type.Boolean, []) == []
      assert TypeDiscovery.traverse_type(:string, []) == []
      assert TypeDiscovery.traverse_type(:integer, []) == []
    end

    test "returns empty list for Map without fields" do
      assert TypeDiscovery.traverse_type(Ash.Type.Map, []) == []
    end

    test "returns empty list for Union without types" do
      assert TypeDiscovery.traverse_type(Ash.Type.Union, []) == []
    end

    test "returns empty list for Struct without instance_of" do
      assert TypeDiscovery.traverse_type(Ash.Type.Struct, []) == []
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

      resources = TypeDiscovery.traverse_fields(fields)

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

      resources = TypeDiscovery.traverse_fields(fields)

      assert AshTypescript.Test.TodoMetadata in resources
    end

    test "returns empty list for invalid input" do
      assert TypeDiscovery.traverse_fields(nil) == []
      assert TypeDiscovery.traverse_fields("invalid") == []
      assert TypeDiscovery.traverse_fields(%{}) == []
    end

    test "returns empty list for fields with no type" do
      fields = [
        invalid_field: [
          constraints: []
        ]
      ]

      assert TypeDiscovery.traverse_fields(fields) == []
    end
  end

  describe "integration: filtering results" do
    test "can filter for non-RPC resources" do
      all_resources = TypeDiscovery.scan_rpc_resources(:ash_typescript)
      rpc_resources = TypeDiscovery.get_rpc_resources(:ash_typescript)

      non_rpc = Enum.reject(all_resources, &(&1 in rpc_resources))

      # Should include embedded resources
      assert AshTypescript.Test.TodoMetadata in non_rpc

      # Should not include RPC resources
      refute AshTypescript.Test.Todo in non_rpc
      refute AshTypescript.Test.User in non_rpc
    end

    test "can filter for embedded resources only" do
      all_resources = TypeDiscovery.scan_rpc_resources(:ash_typescript)

      embedded = Enum.filter(all_resources, &Ash.Resource.Info.embedded?/1)

      # Should include embedded resources
      assert AshTypescript.Test.TodoMetadata in embedded
      assert AshTypescript.Test.TodoContent.TextContent in embedded

      # Should not include non-embedded resources
      refute AshTypescript.Test.Todo in embedded
      refute AshTypescript.Test.User in embedded
    end

    test "can filter for non-embedded, non-RPC resources" do
      all_resources = TypeDiscovery.scan_rpc_resources(:ash_typescript)
      rpc_resources = TypeDiscovery.get_rpc_resources(:ash_typescript)

      non_rpc_non_embedded =
        all_resources
        |> Enum.reject(&(&1 in rpc_resources or Ash.Resource.Info.embedded?(&1)))

      # This should be empty in our test setup, or contain regular resources
      # that are referenced but not exposed as RPC
      assert is_list(non_rpc_non_embedded)
    end
  end

  describe "path tracking: format_path/1" do
    test "formats simple attribute path" do
      path = [{:root, AshTypescript.Test.Todo}, {:attribute, :title}]
      result = TypeDiscovery.format_path(path)

      assert result == "Todo -> title"
    end

    test "formats calculation path" do
      path = [{:root, AshTypescript.Test.Todo}, {:calculation, :computed_value}]
      result = TypeDiscovery.format_path(path)

      assert result == "Todo -> computed_value"
    end

    test "formats aggregate path" do
      path = [{:root, AshTypescript.Test.Todo}, {:aggregate, :comment_count}]
      result = TypeDiscovery.format_path(path)

      assert result == "Todo -> comment_count"
    end

    test "formats union member path" do
      path = [
        {:root, AshTypescript.Test.Todo},
        {:attribute, :content},
        {:union_member, :text}
      ]

      result = TypeDiscovery.format_path(path)

      assert result == "Todo -> content -> (union member: text)"
    end

    test "formats array items path" do
      path = [
        {:root, AshTypescript.Test.Todo},
        {:attribute, :metadata_history},
        :array_items
      ]

      result = TypeDiscovery.format_path(path)

      assert result == "Todo -> metadata_history -> []"
    end

    test "formats map field path" do
      path = [
        {:root, AshTypescript.Test.Todo},
        {:attribute, :config},
        {:map_field, :settings}
      ]

      result = TypeDiscovery.format_path(path)

      assert result == "Todo -> config -> settings"
    end

    test "formats relationship path" do
      path = [
        {:root, AshTypescript.Test.Todo},
        {:aggregate, :first_comment_text},
        {:relationship_path, [:comments]}
      ]

      result = TypeDiscovery.format_path(path)

      assert result == "Todo -> first_comment_text -> (via relationships: comments)"
    end

    test "formats nested path with multiple segments" do
      path = [
        {:root, AshTypescript.Test.Todo},
        {:attribute, :metadata},
        {:attribute, :content},
        {:union_member, :text},
        :array_items
      ]

      result = TypeDiscovery.format_path(path)

      assert result == "Todo -> metadata -> content -> (union member: text) -> []"
    end
  end

  describe "path tracking: find_non_rpc_referenced_resources_with_paths/1" do
    test "returns map with resources as keys and path lists as values" do
      result = TypeDiscovery.find_non_rpc_referenced_resources_with_paths(:ash_typescript)

      assert is_map(result)

      # Each key should be a resource module
      # Each value should be a list of formatted path strings
      Enum.each(result, fn {resource, paths} ->
        assert is_atom(resource)
        assert is_list(paths)
        assert Enum.all?(paths, &is_binary/1)
      end)
    end

    test "excludes RPC resources from results" do
      rpc_resources = TypeDiscovery.get_rpc_resources(:ash_typescript)
      result = TypeDiscovery.find_non_rpc_referenced_resources_with_paths(:ash_typescript)

      result_resources = Map.keys(result)

      # No RPC resources should be in the results
      Enum.each(rpc_resources, fn rpc_resource ->
        refute rpc_resource in result_resources,
               "RPC resource #{inspect(rpc_resource)} should not be in non-RPC results"
      end)
    end

    test "excludes embedded resources from results" do
      result = TypeDiscovery.find_non_rpc_referenced_resources_with_paths(:ash_typescript)

      result_resources = Map.keys(result)

      # No embedded resources should be in the results
      Enum.each(result_resources, fn resource ->
        refute Ash.Resource.Info.embedded?(resource),
               "Embedded resource #{inspect(resource)} should not be in non-RPC results"
      end)
    end

    test "paths show where resources are referenced" do
      result = TypeDiscovery.find_non_rpc_referenced_resources_with_paths(:ash_typescript)

      # Each resource should have at least one path
      Enum.each(result, fn {_resource, paths} ->
        assert paths != [], "Each resource should have at least one reference path"
      end)
    end

    test "deduplicates paths for resources referenced multiple times" do
      result = TypeDiscovery.find_non_rpc_referenced_resources_with_paths(:ash_typescript)

      # Each path list should contain unique paths
      Enum.each(result, fn {_resource, paths} ->
        assert length(paths) == length(Enum.uniq(paths)),
               "Paths should be deduplicated"
      end)
    end

    test "returns empty map when no non-RPC resources are referenced" do
      # Create a mock scenario or use a domain with no non-RPC references
      # For now, we just verify the return type is correct
      result = TypeDiscovery.find_non_rpc_referenced_resources_with_paths(:ash_typescript)

      assert is_map(result)
    end
  end

  describe "path tracking: integration with scan_rpc_resource/2" do
    test "tracks paths through attribute traversal" do
      # Todo has a metadata attribute that references TodoMetadata (embedded)
      # This test verifies paths are being built correctly
      {results, _visited} = TypeDiscovery.scan_rpc_resource(AshTypescript.Test.Todo)

      # Should have found resources with paths
      assert results != []

      # All results should be {resource, path} tuples
      Enum.each(results, fn result ->
        assert match?({_resource, _path}, result)
        {resource, result_path} = result
        assert is_atom(resource)
        assert is_list(result_path)
      end)
    end

    test "paths include root resource" do
      {results, _visited} = TypeDiscovery.scan_rpc_resource(AshTypescript.Test.Todo)

      # All paths should start with {:root, Todo}
      Enum.each(results, fn {_resource, path} ->
        assert [{:root, AshTypescript.Test.Todo} | _rest] = path
      end)
    end

    test "paths correctly represent nested structures" do
      {results, _visited} = TypeDiscovery.scan_rpc_resource(AshTypescript.Test.Todo)

      # Find TodoMetadata in results (from :metadata attribute)
      metadata_results =
        Enum.filter(results, fn {resource, _path} ->
          resource == AshTypescript.Test.TodoMetadata
        end)

      assert metadata_results != []

      # At least one path should go through the :metadata attribute
      has_metadata_attr_path =
        Enum.any?(metadata_results, fn {_resource, path} ->
          {:attribute, :metadata} in path
        end)

      assert has_metadata_attr_path,
             "Should have a path going through metadata attribute"
    end

    test "union member paths are tracked correctly" do
      {results, _visited} = TypeDiscovery.scan_rpc_resource(AshTypescript.Test.Todo)

      # Find union content resources (TextContent, ChecklistContent, LinkContent)
      text_content_results =
        Enum.filter(results, fn {resource, _path} ->
          resource == AshTypescript.Test.TodoContent.TextContent
        end)

      assert text_content_results != []

      # At least one path should include union member marker
      has_union_path =
        Enum.any?(text_content_results, fn {_resource, path} ->
          Enum.any?(path, fn segment ->
            match?({:union_member, _}, segment)
          end)
        end)

      assert has_union_path, "Union member paths should be tracked"
    end

    test "array item paths are tracked correctly" do
      {results, _visited} = TypeDiscovery.scan_rpc_resource(AshTypescript.Test.Todo)

      # Find TodoMetadata in results (from :metadata_history array attribute)
      metadata_results =
        Enum.filter(results, fn {resource, _path} ->
          resource == AshTypescript.Test.TodoMetadata
        end)

      assert metadata_results != []

      # At least one path should include array_items marker
      has_array_path =
        Enum.any?(metadata_results, fn {_resource, path} ->
          :array_items in path
        end)

      assert has_array_path, "Array item paths should be tracked"
    end
  end

  describe "path tracking: backward compatibility" do
    test "scan_rpc_resources/1 still returns just resource modules" do
      result = TypeDiscovery.scan_rpc_resources(:ash_typescript)

      # Should return a list of modules, not tuples
      assert is_list(result)
      assert Enum.all?(result, &is_atom/1)
      refute Enum.any?(result, &match?({_, _}, &1))
    end

    test "find_referenced_resources/1 still returns just resource modules" do
      result = TypeDiscovery.find_referenced_resources(AshTypescript.Test.Todo)

      # Should return a list of modules, not tuples
      assert is_list(result)
      assert Enum.all?(result, &is_atom/1)
      refute Enum.any?(result, &match?({_, _}, &1))
    end

    test "traverse_type/2 still returns just resource modules" do
      result = TypeDiscovery.traverse_type(AshTypescript.Test.TodoMetadata, [])

      # Should return a list of modules, not tuples
      assert is_list(result)
      assert Enum.all?(result, &is_atom/1)
      refute Enum.any?(result, &match?({_, _}, &1))
    end

    test "find_non_rpc_referenced_resources/1 still returns just resource modules" do
      result = TypeDiscovery.find_non_rpc_referenced_resources(:ash_typescript)

      # Should return a list of modules, not tuples
      assert is_list(result)
      assert Enum.all?(result, &is_atom/1)
      refute Enum.any?(result, &match?({_, _}, &1))
    end
  end

  describe "configuration: warning flags" do
    test "build_rpc_warnings respects warn_on_missing_rpc_config flag" do
      # Save original config
      original_missing = Application.get_env(:ash_typescript, :warn_on_missing_rpc_config)
      original_non_rpc = Application.get_env(:ash_typescript, :warn_on_non_rpc_references)

      try do
        # Disable missing RPC config warnings
        Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, false)
        # Keep non-RPC reference warnings enabled to test independence
        Application.put_env(:ash_typescript, :warn_on_non_rpc_references, true)

        # Get warning message
        output = TypeDiscovery.build_rpc_warnings(:ash_typescript)

        # Should not contain missing RPC config warning
        if output do
          refute output =~ "Found resources with AshTypescript.Resource extension"
          refute output =~ "not listed in any domain's typescript_rpc block"
        end

        # But may contain non-RPC reference warnings if they exist
        # (we're just testing that the missing config warning is suppressed)
      after
        # Restore original config
        if original_missing do
          Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, original_missing)
        else
          Application.delete_env(:ash_typescript, :warn_on_missing_rpc_config)
        end

        if original_non_rpc do
          Application.put_env(:ash_typescript, :warn_on_non_rpc_references, original_non_rpc)
        else
          Application.delete_env(:ash_typescript, :warn_on_non_rpc_references)
        end
      end
    end

    test "build_rpc_warnings respects warn_on_non_rpc_references flag" do
      # Save original config
      original_missing = Application.get_env(:ash_typescript, :warn_on_missing_rpc_config)
      original_non_rpc = Application.get_env(:ash_typescript, :warn_on_non_rpc_references)

      try do
        # Keep missing RPC config warnings enabled to test independence
        Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, true)
        # Disable non-RPC reference warnings
        Application.put_env(:ash_typescript, :warn_on_non_rpc_references, false)

        # Get warning message
        output = TypeDiscovery.build_rpc_warnings(:ash_typescript)

        # Should not contain non-RPC reference warning
        if output do
          refute output =~ "Found non-RPC resources referenced by RPC resources"
        end

        # But may contain missing config warnings if they exist
        # (we're just testing that the non-RPC reference warning is suppressed)
      after
        # Restore original config
        if original_missing do
          Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, original_missing)
        else
          Application.delete_env(:ash_typescript, :warn_on_missing_rpc_config)
        end

        if original_non_rpc do
          Application.put_env(:ash_typescript, :warn_on_non_rpc_references, original_non_rpc)
        else
          Application.delete_env(:ash_typescript, :warn_on_non_rpc_references)
        end
      end
    end

    test "both warnings can be disabled simultaneously" do
      # Save original config
      original_missing = Application.get_env(:ash_typescript, :warn_on_missing_rpc_config)
      original_non_rpc = Application.get_env(:ash_typescript, :warn_on_non_rpc_references)

      try do
        # Disable both warnings
        Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, false)
        Application.put_env(:ash_typescript, :warn_on_non_rpc_references, false)

        # Get warning message
        output = TypeDiscovery.build_rpc_warnings(:ash_typescript)

        # Should return nil when all warnings are disabled
        assert output == nil
      after
        # Restore original config
        if original_missing do
          Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, original_missing)
        else
          Application.delete_env(:ash_typescript, :warn_on_missing_rpc_config)
        end

        if original_non_rpc do
          Application.put_env(:ash_typescript, :warn_on_non_rpc_references, original_non_rpc)
        else
          Application.delete_env(:ash_typescript, :warn_on_non_rpc_references)
        end
      end
    end

    test "warnings are enabled by default" do
      # Save original config
      original_missing = Application.get_env(:ash_typescript, :warn_on_missing_rpc_config)
      original_non_rpc = Application.get_env(:ash_typescript, :warn_on_non_rpc_references)

      try do
        # Remove config to test defaults
        Application.delete_env(:ash_typescript, :warn_on_missing_rpc_config)
        Application.delete_env(:ash_typescript, :warn_on_non_rpc_references)

        # Check defaults
        assert AshTypescript.warn_on_missing_rpc_config?() == true
        assert AshTypescript.warn_on_non_rpc_references?() == true
      after
        # Restore original config
        if original_missing do
          Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, original_missing)
        else
          Application.delete_env(:ash_typescript, :warn_on_missing_rpc_config)
        end

        if original_non_rpc do
          Application.put_env(:ash_typescript, :warn_on_non_rpc_references, original_non_rpc)
        else
          Application.delete_env(:ash_typescript, :warn_on_non_rpc_references)
        end
      end
    end

    test "configuration functions return correct values" do
      # Save original config
      original_missing = Application.get_env(:ash_typescript, :warn_on_missing_rpc_config)
      original_non_rpc = Application.get_env(:ash_typescript, :warn_on_non_rpc_references)

      try do
        # Test false values
        Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, false)
        Application.put_env(:ash_typescript, :warn_on_non_rpc_references, false)

        assert AshTypescript.warn_on_missing_rpc_config?() == false
        assert AshTypescript.warn_on_non_rpc_references?() == false

        # Test true values
        Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, true)
        Application.put_env(:ash_typescript, :warn_on_non_rpc_references, true)

        assert AshTypescript.warn_on_missing_rpc_config?() == true
        assert AshTypescript.warn_on_non_rpc_references?() == true
      after
        # Restore original config
        if original_missing do
          Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, original_missing)
        else
          Application.delete_env(:ash_typescript, :warn_on_missing_rpc_config)
        end

        if original_non_rpc do
          Application.put_env(:ash_typescript, :warn_on_non_rpc_references, original_non_rpc)
        else
          Application.delete_env(:ash_typescript, :warn_on_non_rpc_references)
        end
      end
    end
  end

  describe "warning message content" do
    test "missing RPC config warning contains correct explanatory text" do
      # Save original config
      original_missing = Application.get_env(:ash_typescript, :warn_on_missing_rpc_config)
      original_non_rpc = Application.get_env(:ash_typescript, :warn_on_non_rpc_references)

      try do
        # Enable only missing RPC config warnings
        Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, true)
        Application.put_env(:ash_typescript, :warn_on_non_rpc_references, false)

        output = TypeDiscovery.build_rpc_warnings(:ash_typescript)

        if output do
          # Should contain the warning header
          assert output =~ "Found resources with AshTypescript.Resource extension"
          assert output =~ "not listed in any domain's typescript_rpc block"

          # Should explain what this means
          assert output =~ "These resources will not have TypeScript types generated"

          # Should provide guidance on how to fix
          assert output =~ "To fix this, add them to a domain's typescript_rpc block"
        end
      after
        # Restore original config
        if original_missing do
          Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, original_missing)
        else
          Application.delete_env(:ash_typescript, :warn_on_missing_rpc_config)
        end

        if original_non_rpc do
          Application.put_env(:ash_typescript, :warn_on_non_rpc_references, original_non_rpc)
        else
          Application.delete_env(:ash_typescript, :warn_on_non_rpc_references)
        end
      end
    end

    test "non-RPC references warning states NO types are generated" do
      # Save original config
      original_missing = Application.get_env(:ash_typescript, :warn_on_missing_rpc_config)
      original_non_rpc = Application.get_env(:ash_typescript, :warn_on_non_rpc_references)

      try do
        # Enable only non-RPC reference warnings
        Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, false)
        Application.put_env(:ash_typescript, :warn_on_non_rpc_references, true)

        output = TypeDiscovery.build_rpc_warnings(:ash_typescript)

        if output do
          # Should contain the warning header
          assert output =~ "Found non-RPC resources referenced by RPC resources"

          # CRITICAL: Should state that NO types are generated
          assert output =~ "will NOT have TypeScript types or RPC functions generated"

          # Should NOT contain the old incorrect message
          refute output =~ "will have basic TypeScript types generated"

          # Should provide guidance
          assert output =~
                   "If these resources should be accessible via RPC, add them to a domain's"

          assert output =~ "typescript_rpc block. Otherwise, you can ignore this warning"
        end
      after
        # Restore original config
        if original_missing do
          Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, original_missing)
        else
          Application.delete_env(:ash_typescript, :warn_on_missing_rpc_config)
        end

        if original_non_rpc do
          Application.put_env(:ash_typescript, :warn_on_non_rpc_references, original_non_rpc)
        else
          Application.delete_env(:ash_typescript, :warn_on_non_rpc_references)
        end
      end
    end

    test "warning message includes proper formatting with emoji and indentation" do
      # Save original config
      original_missing = Application.get_env(:ash_typescript, :warn_on_missing_rpc_config)
      original_non_rpc = Application.get_env(:ash_typescript, :warn_on_non_rpc_references)

      try do
        # Enable both warnings
        Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, true)
        Application.put_env(:ash_typescript, :warn_on_non_rpc_references, true)

        output = TypeDiscovery.build_rpc_warnings(:ash_typescript)

        if output do
          # Should use warning emoji
          assert output =~ "⚠️"

          # Should have proper bullet points for resources
          assert output =~ "   •"

          # If there are two warnings, they should be separated by double newline
          if output =~ "Found resources with AshTypescript.Resource extension" and
               output =~ "Found non-RPC resources referenced by RPC resources" do
            # Check that warnings are separated
            assert String.contains?(output, "\n\n")
          end
        end
      after
        # Restore original config
        if original_missing do
          Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, original_missing)
        else
          Application.delete_env(:ash_typescript, :warn_on_missing_rpc_config)
        end

        if original_non_rpc do
          Application.put_env(:ash_typescript, :warn_on_non_rpc_references, original_non_rpc)
        else
          Application.delete_env(:ash_typescript, :warn_on_non_rpc_references)
        end
      end
    end
  end
end
