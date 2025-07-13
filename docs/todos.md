# Test Failures Analysis & Fix Guide

This document outlines the current test failures and provides context for fixing them.

## 1. TypeScript Codegen Test Failure

**File**: `test/ts_codegen_test.exs:298`  
**Test**: "converts struct with instance_of to resource type"  
**Failure**: `assert String.contains?(result, "id: UUID;")` returns false

### Issue Summary
The `get_ts_type/2` function is returning `"TodoResourceSchema"` instead of generating a proper TypeScript interface when handling `Ash.Type.Struct` with `instance_of: Todo` constraints.

### Root Cause
The codegen logic for `Ash.Type.Struct` with `instance_of` constraints isn't properly generating the full resource type definition with individual fields like `id: UUID;`.

### Fix Approach
- Check the `Codegen.get_ts_type/1` function in `lib/ash_typescript/codegen.ex`
- Ensure that when `constraints[:instance_of]` is present, the function generates the actual TypeScript interface for the resource instead of just returning the schema name
- The generated interface should include all public attributes of the resource with their proper TypeScript types

---

## 2. RPC Validation Error Format Mismatch

**File**: `test/rpc_test.exs:479`  
**Test**: "validates update actions with errors"  
**Failure**: `Map.has_key?(field_errors, "title")` returns false

### Issue Summary
The validation error response structure has changed. The test expects field errors with string keys, but the actual response has atom keys.

### Root Cause
The error response format in the RPC validation logic has changed from `%{"title" => "is required"}` to `%{title: "is required"}` (string keys vs atom keys).

### Fix Approach
- Update the test to use atom keys: `Map.has_key?(field_errors, :title)`
- Or update the RPC error formatting to ensure consistent string keys in the response
- Check `lib/ash_typescript/rpc.ex` around the `validate_action/3` function for error formatting logic

---

## 3. Complex Calculation Argument Handling

**File**: `test/rpc_test.exs:1265`  
**Test**: "calculations parameter can now handle field selection for calculations with arguments"  
**Failure**: `BadMapError: expected a map, got: nil`

### Issue Summary
The RPC calculation argument processing fails when handling `nil` values in calculation arguments, specifically in the argument atomization logic.

### Root Cause
In `lib/ash_typescript/rpc.ex` lines 434-436, the code attempts to process calculation arguments:
```elixir
args_atomized = 
  Enum.reduce(args, %{}, fn {k, v}, acc ->
    Map.put(acc, String.to_existing_atom(k), v)
  end)
```
When `args` contains `%{"prefix" => nil}`, the `nil` value is causing issues in Ash's argument validation pipeline.

### Fix Approach
- Add nil handling in the argument processing logic
- Use `Ash.Type.cast_input/3` with proper nil checking before passing to Ash's validation
- Consider filtering out nil arguments or providing proper default values based on the calculation's argument definitions
- The issue is likely in the `parse_calculations_with_fields/2` function

---

## 4. Error Class Format Change

**File**: `test/rpc_test.exs:522`  
**Test**: "returns error for invalid primary key in update validation"  
**Failure**: Expected binary string, got atom `:invalid`

### Issue Summary
The error response format has changed - the test expects `error_class` to be a binary string but it's returning the atom `:invalid`.

### Root Cause
The error classification logic in the RPC layer has changed to return atoms instead of strings for error classes.

### Fix Approach
- Update the test assertion to expect atoms: `assert is_atom(error_class)`
- Or update the RPC error formatting to convert error classes to strings before returning
- Check error handling in `validate_action/3` function

---

## 5. Error Classification Change

**File**: `test/rpc_test.exs:540`  
**Test**: "returns error for non-existent record in update validation"  
**Failure**: Expected `class: "forbidden"` but got `class: :invalid`

### Issue Summary
The error classification logic has changed. When a record is not found, it now returns `class: :invalid` instead of `class: "forbidden"`.

### Root Cause
The error classification in Ash or the RPC layer has changed how it categorizes "not found" errors - they're now classified as `:invalid` rather than `:forbidden`.

### Fix Approach
- Update the test to expect the correct error class: `class: :invalid`
- Verify this is the intended behavior by checking Ash's error classification logic
- Consider if this is a breaking change that needs documentation

---

## General Recommendations

1. **Run tests individually** to isolate issues: `mix test test/rpc_test.exs:479`
2. **Check error formatting consistency** across all RPC endpoints
3. **Verify Ash framework version compatibility** - some changes might be due to Ash framework updates
4. **Update error handling tests** to match the new error response format
5. **Consider backward compatibility** when fixing error response formats

## Files to Review

- `lib/ash_typescript/rpc.ex` - Main RPC implementation and error handling
- `lib/ash_typescript/codegen.ex` - TypeScript type generation logic
- `test/rpc_test.exs` - Update test expectations to match new behavior
- `test/ts_codegen_test.exs` - Verify codegen expectations