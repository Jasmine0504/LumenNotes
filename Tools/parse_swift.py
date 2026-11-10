import sys
from pathlib import Path

import tree_sitter
import tree_sitter_swift

language = tree_sitter.Language(tree_sitter_swift.language())
parser = tree_sitter.Parser(language)
root = Path(r"D:\DSH专用文件夹\LumenNotes")
bad = []


def walk(node, source, errors):
    if node.type == "ERROR" or node.is_missing:
        errors.append((node.start_point[0] + 1, node.type, source[node.start_byte:node.end_byte][:100]))
    for child in node.children:
        walk(child, source, errors)


for path in sorted(root.rglob("*.swift")):
    source = path.read_bytes()
    tree = parser.parse(source)
    errors = []
    walk(tree.root_node, source, errors)
    if errors:
        bad.append((path, errors))

for path, errors in bad:
    print(path.relative_to(root))
    for line, kind, text in errors[:10]:
        print(f"  {line}: {kind} {text!r}")

print(f"\n{len(bad)} files with parse errors out of {len(list(root.rglob('*.swift')))}")
sys.exit(1 if bad else 0)
