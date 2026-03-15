import re
import os

BASE = '/Users/tgk/src/ash_typescript'

files = [
    'test/ash_typescript/rpc/calculation_field_selection_test.exs',
    'test/ash_typescript/rpc/keyword_field_validation_test.exs',
    'test/ash_typescript/rpc/requested_fields_processor_aggregates_test.exs',
    'test/ash_typescript/rpc/requested_fields_processor_calculations_test.exs',
    'test/ash_typescript/rpc/requested_fields_processor_crud_test.exs',
    'test/ash_typescript/rpc/requested_fields_processor_custom_types_test.exs',
    'test/ash_typescript/rpc/requested_fields_processor_embedded_test.exs',
    'test/ash_typescript/rpc/requested_fields_processor_generic_actions_test.exs',
    'test/ash_typescript/rpc/requested_fields_processor_keyword_test.exs',
    'test/ash_typescript/rpc/requested_fields_processor_relationships_test.exs',
    'test/ash_typescript/rpc/requested_fields_processor_test.exs',
    'test/ash_typescript/rpc/requested_fields_processor_tuple_test.exs',
    'test/ash_typescript/rpc/requested_fields_processor_typed_structs_test.exs',
    'test/ash_typescript/rpc/requested_fields_processor_union_types_test.exs',
]

def find_matching_paren(text, start):
    """Find the matching closing paren for the opening paren at position start."""
    depth = 0
    i = start
    while i < len(text):
        c = text[i]
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                return i
        elif c == '"':
            # Skip string
            i += 1
            while i < len(text) and text[i] != '"':
                if text[i] == '\\':
                    i += 1  # skip escaped char
                i += 1
        i += 1
    return -1

def count_commas_at_depth_0(text):
    """Count commas at depth 0 (direct args) in the given text."""
    depth = 0
    commas = 0
    i = 0
    while i < len(text):
        c = text[i]
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
        elif c == ',' and depth == 0:
            commas += 1
        elif c == '"':
            i += 1
            while i < len(text) and text[i] != '"':
                if text[i] == '\\':
                    i += 1
                i += 1
        i += 1
    return commas

def process_file(filepath):
    with open(filepath) as f:
        content = f.read()

    # Step 1: Add @resource_lookups module attribute if not present
    if '@resource_lookups' not in content:
        lines = content.split('\n')
        insert_idx = None
        for i, line in enumerate(lines):
            stripped = line.strip()
            if stripped.startswith('alias ') or stripped.startswith('use '):
                insert_idx = i + 1

        if insert_idx is not None:
            lines.insert(insert_idx, '')
            lines.insert(insert_idx + 1, '  @resource_lookups AshTypescript.resource_lookup(:ash_typescript)')
            content = '\n'.join(lines)

    # Step 2: Find all RequestedFieldsProcessor.process( calls and add @resource_lookups
    pattern = 'RequestedFieldsProcessor.process('
    result = []
    i = 0
    modifications = 0

    while i < len(content):
        pos = content.find(pattern, i)
        if pos == -1:
            result.append(content[i:])
            break

        # Add everything before this match
        result.append(content[i:pos])

        # Find the opening paren
        paren_start = pos + len(pattern) - 1  # position of '('
        paren_end = find_matching_paren(content, paren_start)

        if paren_end == -1:
            result.append(content[pos:pos + len(pattern)])
            i = pos + len(pattern)
            continue

        # Get the arguments section (between parens)
        args_text = content[paren_start + 1:paren_end]

        # Count how many top-level args there are
        num_commas = count_commas_at_depth_0(args_text)
        num_args = num_commas + 1

        if num_args == 3:
            # 3-arg call -> add @resource_lookups as 4th arg before closing paren
            result.append(content[pos:paren_end])
            result.append(', @resource_lookups)')
            modifications += 1
            i = paren_end + 1
        else:
            # Already has 4+ args, or different count - skip
            result.append(content[pos:paren_end + 1])
            i = paren_end + 1

    new_content = ''.join(result)

    with open(filepath, 'w') as f:
        f.write(new_content)

    print(f'{filepath}: {modifications} calls modified')

for f in files:
    filepath = os.path.join(BASE, f)
    process_file(filepath)
