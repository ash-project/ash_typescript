defmodule AshTypescript.Rpc.ExtractionTemplateTest do
  use ExUnit.Case, async: true

  alias AshTypescript.Rpc.ExtractionTemplate
  alias AshTypescript.Rpc.ResultProcessorNew
  alias AshTypescript.Rpc.FieldParser

  describe "ExtractionTemplate" do
    test "creates basic extraction instructions" do
      template = ExtractionTemplate.new()
      
      template = 
        template
        |> ExtractionTemplate.put_instruction("id", ExtractionTemplate.extract_field(:id))
        |> ExtractionTemplate.put_instruction("title", ExtractionTemplate.extract_field(:title))

      assert %{
        "id" => {:extract, :id},
        "title" => {:extract, :title}
      } = template
    end

    test "validates templates correctly" do
      valid_template = %{
        "id" => {:extract, :id},
        "user" => {:nested, :user, %{"name" => {:extract, :name}}}
      }

      assert :ok = ExtractionTemplate.validate(valid_template)

      invalid_template = %{
        "bad" => {:invalid_instruction, :bad}
      }

      assert {:error, _} = ExtractionTemplate.validate(invalid_template)
    end
  end

  describe "ResultProcessorNew" do
    test "extracts simple fields correctly" do
      template = %{
        "id" => {:extract, :id},
        "title" => {:extract, :title}
      }

      data = %{
        id: "123",
        title: "Test Todo",
        description: "Should not appear"
      }

      result = ResultProcessorNew.extract_fields(data, template)

      assert %{
        "id" => "123",
        "title" => "Test Todo"
      } = result

      # Ensure filtered field doesn't appear
      refute Map.has_key?(result, "description")
    end

    test "handles nested resource extraction" do
      nested_template = %{
        "name" => {:extract, :name}
      }

      template = %{
        "id" => {:extract, :id},
        "user" => {:nested, :user, nested_template}
      }

      data = %{
        id: "123",
        user: %{
          name: "John",
          email: "john@example.com"
        }
      }

      result = ResultProcessorNew.extract_fields(data, template)

      assert %{
        "id" => "123",
        "user" => %{"name" => "John"}
      } = result

      # Ensure nested field is filtered
      refute Map.has_key?(result["user"], "email")
    end

    test "handles arrays of nested resources" do
      nested_template = %{
        "name" => {:extract, :name}
      }

      template = %{
        "id" => {:extract, :id},
        "users" => {:nested, :users, nested_template}
      }

      data = %{
        id: "123",
        users: [
          %{name: "John", email: "john@example.com"},
          %{name: "Jane", email: "jane@example.com"}
        ]
      }

      result = ResultProcessorNew.extract_fields(data, template)

      assert %{
        "id" => "123",
        "users" => [
          %{"name" => "John"},
          %{"name" => "Jane"}
        ]
      } = result
    end

    test "handles Ash.NotLoaded values gracefully" do
      template = %{
        "id" => {:extract, :id},
        "user" => {:nested, :user, %{"name" => {:extract, :name}}}
      }

      data = %{
        id: "123",
        user: %Ash.NotLoaded{type: :relationship, field: :user}
      }

      result = ResultProcessorNew.extract_fields(data, template)

      assert %{
        "id" => "123",
        "user" => nil
      } = result
    end

    test "handles pagination correctly" do
      template = %{
        "id" => {:extract, :id},
        "title" => {:extract, :title}
      }

      page = %Ash.Page.Offset{
        results: [
          %{id: "1", title: "Todo 1", description: "Should not appear"},
          %{id: "2", title: "Todo 2", description: "Should not appear"}
        ],
        limit: 10,
        offset: 0,
        more?: false
      }

      result = ResultProcessorNew.extract_fields(page, template)

      assert %{
        "results" => [
          %{"id" => "1", "title" => "Todo 1"},
          %{"id" => "2", "title" => "Todo 2"}
        ],
        "limit" => 10,
        "offset" => 0,
        "hasMore" => false,
        "type" => "offset"
      } = result

      # Ensure filtered fields don't appear
      Enum.each(result["results"], fn item ->
        refute Map.has_key?(item, "description")
      end)
    end
  end

  describe "FieldParser integration" do
    test "generates extraction templates for simple fields" do
      fields = ["id", "title"]
      resource = AshTypescript.Test.Todo
      formatter = :camel_case

      {select, load, extraction_template} = 
        FieldParser.parse_requested_fields(fields, resource, formatter)

      assert [:id, :title] = select
      assert [] = load
      assert %{
        "id" => {:extract, :id},
        "title" => {:extract, :title}
      } = extraction_template
    end

    test "generates nested templates for relationship fields" do
      fields = [%{"user" => ["name", "email"]}]
      resource = AshTypescript.Test.Todo
      formatter = :camel_case

      {select, load, extraction_template} = 
        FieldParser.parse_requested_fields(fields, resource, formatter)

      assert [] = select
      assert [{:user, [:name, :email]}] = load
      
      # The extraction template should have a nested structure
      assert %{"user" => {:nested, :user, nested_template}} = extraction_template
      assert %{
        "name" => {:extract, :name},
        "email" => {:extract, :email}
      } = nested_template
    end
  end
end