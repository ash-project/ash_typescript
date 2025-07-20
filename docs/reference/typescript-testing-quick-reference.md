# TypeScript Codegen Testing Quick Reference

## 🚨 CRITICAL RULE: Always Use Regex, Never String.contains?

### Quick Decision Matrix

| Testing Scenario | Use This Pattern | Why |
|------------------|------------------|-----|
| TypeScript type structure | ✅ Regex patterns | Validates complete structure, field order, syntax |
| Individual field presence | ✅ Regex patterns | Ensures proper context and optional markers |
| Error messages/logs | ⚠️ String.contains? OK | Simple string matching for debug output |
| Generated code validation | ✅ Regex patterns ONLY | Critical for type safety and structure integrity |

## Essential Regex Templates

### Basic Config Type Template
```elixir
# Template for any config type validation
config_regex = ~r/export type #{ConfigName} = \{\s*#{field_pattern}\s*\};/m
```

### Common Field Patterns
```elixir
# Required field
"fieldName: FieldType"

# Optional field  
"fieldName\?\: FieldType"

# Array field
"fields: UnifiedFieldSelection<ResourceSchema>\[\]"

# Nested object
"page\?\: \{\s*limit\?\: number;\s*offset\?\: number;\s*\}"

# Union type
"status\?\: \"pending\" \| \"complete\""

# Record type
"headers\?\: Record<string, string>"
```

### Action Type Patterns

#### Get Action (No Pagination)
```elixir
get_action_regex =
  ~r/export type GetTodoConfig = \{\s*input\?\: \{[^}]*\};\s*fields: UnifiedFieldSelection<TodoResourceSchema>\[\];\s*headers\?\: Record<string, string>;\s*\};/m
```

#### List Action (With Pagination)
```elixir
list_action_regex =
  ~r/export type ListTodosConfig = \{\s*input\?\: \{[^}]*\};\s*filter\?\: TodoFilterInput;\s*sort\?\: string;\s*page\?\: \{[^}]*\};\s*fields: UnifiedFieldSelection<TodoResourceSchema>\[\];\s*headers\?\: Record<string, string>;\s*\};/m
```

#### Multitenant Action (Tenant First)
```elixir
multitenant_regex =
  ~r/export type ListOrgTodosConfig = \{\s*tenant: string;\s*input\?\: \{[^}]*\};\s*filter\?\: [^;]+;\s*sort\?\: string;\s*page\?\: \{[^}]*\};\s*fields: [^}]+\[\];\s*headers\?\: [^}]+;\s*\};/m
```

#### Create/Update Action
```elixir
# Create action (required input)
create_regex =
  ~r/export type CreateTodoConfig = \{\s*input: \{[\s\S]*?title: string;[\s\S]*?\};\s*fields: UnifiedFieldSelection<TodoResourceSchema>\[\];\s*headers\?\: Record<string, string>;\s*\};/m

# Update action (primaryKey + input)  
update_regex =
  ~r/export type UpdateTodoConfig = \{\s*primaryKey: UUID;\s*input: \{[\s\S]*?title: string;[\s\S]*?\};\s*fields: UnifiedFieldSelection<TodoResourceSchema>\[\];\s*headers\?\: Record<string, string>;\s*\};/m
```

## Common Test Patterns

### Complete Structure Validation
```elixir
test "generates complete config structure" do
  typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

  config_regex = ~r/export type ConfigName = \{#{complete_field_pattern}\};/m
  
  assert Regex.match?(config_regex, typescript_output),
         "ConfigName structure is malformed. Expected complete type definition with all fields in correct order"
end
```

### Comparative Validation (Get vs List)
```elixir
test "get actions exclude pagination, list actions include it" do
  typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

  # Get action should NOT have sort/page
  get_regex = ~r/GetTodoConfig = \{[^}]*\};\s*fields: [^}]+;\s*headers\?\: [^}]+;\s*\};/m
  refute String.match?(get_regex, "sort\\?\\:"),
         "GetTodoConfig should not contain sort field"

  # List action SHOULD have sort/page
  list_regex = ~r/ListTodosConfig = \{[^}]*sort\?\: string;[^}]*page\?\: \{[^}]*\}[^}]*\};/m
  assert Regex.match?(list_regex, typescript_output),
         "ListTodosConfig should contain both sort and page fields"
end
```

### Input Block Validation
```elixir
test "input block has correct argument structure" do
  typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

  input_regex =
    ~r/input\?\: \{\s*filterCompleted\?\: boolean;\s*priorityFilter\?\: "low" \| "medium" \| "high" \| "urgent";\s*\}/m

  assert Regex.match?(input_regex, typescript_output),
         "Input block arguments must have correct types and optional markers"
end
```

## Regex Construction Tips

### Handle Multiline Content
```elixir
# For single-line simple content
~r/\{[^}]*\}/m

# For multiline complex content (input blocks with many fields)
~r/\{[\s\S]*?\}/m

# Example: Large input block
~r/input: \{[\s\S]*?title: string;[\s\S]*?\}/m
```

### Escape Special Characters
```elixir
# TypeScript special characters that need escaping
"UnifiedFieldSelection<TodoResourceSchema>\\[\\]"  # Arrays
"Record<string, string>"                           # Records  
"\"pending\" \\| \"complete\""                     # Unions
"fieldName\\?\\:"                                  # Optional markers
```

### Common Mistakes to Avoid

#### ❌ DON'T: Fragmented Testing
```elixir
# BAD - Tests fields separately
assert String.contains?(output, "sort?:")
assert String.contains?(output, "page?:")
```

#### ❌ DON'T: Ignore Field Order
```elixir
# BAD - Order matters in TypeScript!
~r/\{.*sort.*page.*\}/  # Wrong - doesn't enforce order
```

#### ❌ DON'T: Skip Optional Markers
```elixir
# BAD - Misses required vs optional distinction
~r/sort: string/  # Wrong - should be "sort\?\: string"
```

## Error Message Best Practices

### ✅ GOOD: Descriptive with Context
```elixir
assert Regex.match?(config_regex, typescript_output),
       "GetTodoConfig structure is malformed. Get actions should not have sort or page fields, only input, fields, and headers"
```

### ❌ BAD: Vague Error Message
```elixir
assert Regex.match?(config_regex, typescript_output),
       "Config is wrong"
```

## Validation Checklist

Before any TypeScript codegen test:

- [ ] ✅ Using regex patterns (not String.contains?)
- [ ] ✅ Validating complete structure (not just field presence)  
- [ ] ✅ Testing field order and optional markers
- [ ] ✅ Including descriptive error messages
- [ ] ✅ Testing both positive and negative cases
- [ ] ✅ Handling multiline content correctly
- [ ] ✅ Escaping TypeScript special characters

## Quick Examples by Scenario

### Testing New Action Type
```elixir
test "new action generates correct structure" do
  typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

  # Define complete expected structure
  new_action_regex = ~r/export type NewActionConfig = \{[complete_pattern]\};/m
  
  assert Regex.match?(new_action_regex, typescript_output),
         "NewActionConfig structure is malformed. Expected [describe expected structure]"
end
```

### Testing Feature Addition
```elixir
test "feature addition maintains existing structure" do
  typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

  # Test that existing patterns still work
  existing_regex = ~r/existing_pattern/m
  assert Regex.match?(existing_regex, typescript_output),
         "Feature addition broke existing structure"
         
  # Test that new feature is present
  new_feature_regex = ~r/new_feature_pattern/m
  assert Regex.match?(new_feature_regex, typescript_output),
         "New feature not properly integrated"
end
```

### Testing Regression Prevention
```elixir
test "change doesn't break pagination exclusion for get actions" do
  typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

  # Get actions should still exclude pagination
  get_action_regex = ~r/GetTodoConfig = \{[^}]*\};\s*fields: [^}]+;\s*headers\?\: [^}]+;\s*\};/m
  
  refute Regex.match?(~r/GetTodoConfig.*sort\?\:/, typescript_output),
         "Regression: Get actions should not have sort field"
  refute Regex.match?(~r/GetTodoConfig.*page\?\:/, typescript_output),
         "Regression: Get actions should not have page field"
end
```

---

**Remember**: TypeScript structure integrity is critical for type safety. Regex patterns catch issues that String.contains? misses.