defmodule AshApiSpec.JsonSerializerTest do
  use ExUnit.Case, async: true

  alias AshApiSpec.JsonSerializer

  describe "to_json/2" do
    test "serializes a full spec to valid JSON" do
      {:ok, spec} = AshApiSpec.generate(otp_app: :ash_typescript)
      {:ok, json} = JsonSerializer.to_json(spec)

      assert is_binary(json)
      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["version"] == "1.0.0"
      assert is_list(decoded["resources"])
    end

    test "pretty option produces formatted JSON" do
      {:ok, spec} = AshApiSpec.generate(otp_app: :ash_typescript)
      {:ok, json} = JsonSerializer.to_json(spec, pretty: true)

      assert String.contains?(json, "\n")
    end

    test "resources have expected structure" do
      {:ok, spec} = AshApiSpec.generate(otp_app: :ash_typescript)
      {:ok, json} = JsonSerializer.to_json(spec)
      {:ok, decoded} = Jason.decode(json)

      todo = Enum.find(decoded["resources"], &(&1["name"] == "Todo"))
      assert todo != nil
      assert is_binary(todo["module"])
      assert is_boolean(todo["embedded"])
      assert is_list(todo["primary_key"])
      assert is_map(todo["fields"])
      assert is_map(todo["relationships"])
      assert is_map(todo["actions"])
    end

    test "fields have expected structure" do
      {:ok, spec} = AshApiSpec.generate(otp_app: :ash_typescript)
      {:ok, json} = JsonSerializer.to_json(spec)
      {:ok, decoded} = Jason.decode(json)

      todo = Enum.find(decoded["resources"], &(&1["name"] == "Todo"))
      title = todo["fields"]["title"]

      assert title["kind"] == "attribute"
      assert title["type"]["kind"] == "string"
      assert title["allow_nil"] == false
      assert is_boolean(title["writable"])
      assert is_boolean(title["primary_key"])
    end

    test "relationships have expected structure" do
      {:ok, spec} = AshApiSpec.generate(otp_app: :ash_typescript)
      {:ok, json} = JsonSerializer.to_json(spec)
      {:ok, decoded} = Jason.decode(json)

      todo = Enum.find(decoded["resources"], &(&1["name"] == "Todo"))
      user_rel = todo["relationships"]["user"]

      assert user_rel["type"] == "belongs_to"
      assert user_rel["cardinality"] == "one"
      assert is_binary(user_rel["destination"])
    end

    test "actions have expected structure" do
      {:ok, spec} = AshApiSpec.generate(otp_app: :ash_typescript)
      {:ok, json} = JsonSerializer.to_json(spec)
      {:ok, decoded} = Jason.decode(json)

      todo = Enum.find(decoded["resources"], &(&1["name"] == "Todo"))
      read_action = todo["actions"]["read"]

      assert read_action["type"] == "read"
      assert is_boolean(read_action["primary"])
      assert is_list(read_action["arguments"])
    end

    test "pagination is serialized when present" do
      {:ok, spec} = AshApiSpec.generate(otp_app: :ash_typescript)
      {:ok, json} = JsonSerializer.to_json(spec)
      {:ok, decoded} = Jason.decode(json)

      todo = Enum.find(decoded["resources"], &(&1["name"] == "Todo"))
      read_action = todo["actions"]["read"]

      assert read_action["pagination"] != nil
      assert is_boolean(read_action["pagination"]["offset"])
      assert is_boolean(read_action["pagination"]["keyset"])
    end

    test "generic action returns type is serialized" do
      {:ok, spec} = AshApiSpec.generate(otp_app: :ash_typescript)
      {:ok, json} = JsonSerializer.to_json(spec)
      {:ok, decoded} = Jason.decode(json)

      todo = Enum.find(decoded["resources"], &(&1["name"] == "Todo"))
      bulk_complete = todo["actions"]["bulk_complete"]

      if bulk_complete do
        assert bulk_complete["returns"] != nil
        assert bulk_complete["returns"]["kind"] == "array"
      end
    end

    test "nil fields are omitted from JSON" do
      {:ok, spec} = AshApiSpec.generate(otp_app: :ash_typescript)
      {:ok, json} = JsonSerializer.to_json(spec)
      {:ok, decoded} = Jason.decode(json)

      todo = Enum.find(decoded["resources"], &(&1["name"] == "Todo"))

      # Attribute fields should not have "arguments" key (only calculations have that)
      title = todo["fields"]["title"]
      refute Map.has_key?(title, "arguments")
    end

    test "module atoms are converted to strings" do
      {:ok, spec} = AshApiSpec.generate(otp_app: :ash_typescript)
      {:ok, json} = JsonSerializer.to_json(spec)
      {:ok, decoded} = Jason.decode(json)

      todo = Enum.find(decoded["resources"], &(&1["name"] == "Todo"))
      assert is_binary(todo["module"])
      assert String.contains?(todo["module"], "Todo")
    end
  end

  describe "to_map/1" do
    test "converts spec to plain map" do
      {:ok, spec} = AshApiSpec.generate(otp_app: :ash_typescript)
      map = JsonSerializer.to_map(spec)

      assert is_map(map)
      assert map["version"] == "1.0.0"
      assert is_list(map["resources"])
    end
  end
end
