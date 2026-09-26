"""Structural checks usable on Windows. These do not replace an Xcode build."""
from pathlib import Path
import json
import plistlib
import sys
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root.parent / 'scratch/ios-validation'))
from tree_sitter import Language, Parser
import tree_sitter_swift
from openstep_parser import OpenStepDecoder

parser = Parser(Language(tree_sitter_swift.language()))
errors = []
sources = list(root.rglob('*.swift'))
for source in sources:
    tree = parser.parse(source.read_bytes())
    def walk(node):
        if node.type == 'ERROR' or node.is_missing:
            errors.append(f'{source.relative_to(root)}:{node.start_point.row + 1}: syntax node {node.type}: {node.text[:120]!r}')
        for child in node.children:
            walk(child)
    walk(tree.root_node)
for pattern in ('*.plist', '*.entitlements', '*.xcprivacy'):
    for source in root.rglob(pattern):
        with source.open('rb') as stream:
            plistlib.load(stream)
for source in root.rglob('Contents.json'):
    json.loads(source.read_text())
for source in root.rglob('*.xcscheme'):
    ET.parse(source)
with (root / 'NeonWave.xcodeproj/project.pbxproj').open(encoding='utf-8') as stream:
    project = OpenStepDecoder.ParseFromFile(stream)
objects = project['objects']
for value in objects.values():
    if value.get('isa') == 'PBXFileReference' and value.get('sourceTree') == '<group>':
        assert (root / value['path']).exists(), value['path']
    if value.get('isa') == 'PBXBuildFile':
        assert value['fileRef'] in objects
    if value.get('isa') == 'PBXNativeTarget':
        assert all(phase in objects for phase in value['buildPhases'])
if errors:
    print('\n'.join(errors)); sys.exit(1)
print(f'PASS: parsed {len(sources)} Swift files, Xcode references, schemes, property lists and asset manifests.')
print('Not compiled: SwiftUI type checking, signing and runtime tests require macOS/Xcode.')
