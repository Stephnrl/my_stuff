#!/usr/bin/env python3
"""
tf_docgen.py — Generate HTML documentation from Terraform module directories.

Handles both layouts you described:
  * Monolithic repos: main.tf / variables.tf / outputs.tf in the root.
  * Multi-module repos: subdirectories like EKS/, pod_identity/, S3/, RDS/,
    each with their own .tf files. Every directory containing .tf files is
    documented as a separate module.

For each module the report includes:
  * Description (pulled from README.md, falls back to top-of-file comments)
  * Auto-generated Usage example (required vars first, optionals with defaults)
  * Inputs / Outputs tables
  * Resources, data sources, sub-modules, required providers
  * Mermaid diagram of the module's structure

The output is a single self-contained HTML file. Open it in a browser to view
(diagrams render via the Mermaid CDN), or paste sections into Confluence —
tables and headings copy across cleanly. Mermaid source is also exposed in a
<details> block so you can drop it into a Confluence Mermaid macro.

Usage:
    pip install python-hcl2
    python tf_docgen.py                        # scan current directory
    python tf_docgen.py /path/to/repo          # scan a specific path
    python tf_docgen.py -o eks-docs.html       # custom output file
    python tf_docgen.py --title "EKS Modules"  # custom report title
"""

import argparse
import json
import os
import re
import sys
from datetime import datetime
from html import escape
from pathlib import Path

try:
    import hcl2
except ImportError:
    sys.stderr.write(
        "ERROR: python-hcl2 is required.\n"
        "Install it with:  pip install python-hcl2\n"
    )
    sys.exit(1)


# Directories that should never count as "modules"
SKIP_DIRS = {
    ".terraform", ".git", ".github", ".idea", ".vscode",
    "node_modules", "examples", "example", "test", "tests", "__pycache__",
}


# ---------- discovery ----------

def find_module_dirs(root: Path):
    """Return every directory under `root` that contains at least one .tf file."""
    root = root.resolve()
    found = set()

    def walk(d: Path):
        if d.name in SKIP_DIRS or (d != root and d.name.startswith('.')):
            return
        try:
            entries = list(d.iterdir())
        except (PermissionError, OSError):
            return
        if any(p.suffix == '.tf' and p.is_file() for p in entries):
            found.add(d)
        for sub in entries:
            if sub.is_dir():
                walk(sub)

    walk(root)
    return sorted(found, key=lambda p: str(p).lower())


# ---------- HCL parsing ----------

def _unwrap(value):
    """Strip the ${...} wrapping that python-hcl2 puts around expressions/types."""
    if isinstance(value, str):
        m = re.fullmatch(r'\$\{(.*)\}', value, flags=re.DOTALL)
        if m:
            return m.group(1)
        return value
    if isinstance(value, list):
        return [_unwrap(v) for v in value]
    if isinstance(value, dict):
        return {k: _unwrap(v) for k, v in value.items()}
    return value


def _stringify(val):
    """Coerce parser output (sometimes wrapped in lists) to a clean string."""
    if val is None:
        return ''
    if isinstance(val, list):
        return ' '.join(_stringify(x) for x in val).strip()
    return _strip_quotes(str(val).strip())


def _strip_quotes(s):
    """Strip surrounding quote characters that some python-hcl2 versions retain."""
    if not isinstance(s, str):
        return s
    if len(s) >= 2 and s[0] == s[-1] and s[0] in ('"', "'"):
        inner = s[1:-1]
        # Only strip if there's no unescaped quote of the same kind inside
        if s[0] not in inner.replace('\\' + s[0], ''):
            return inner.replace('\\' + s[0], s[0])
    return s


def _clean_value(val):
    """Recursively clean parser output: strip quote wrapping, drop __is_block__."""
    if isinstance(val, str):
        return _strip_quotes(val)
    if isinstance(val, list):
        return [_clean_value(v) for v in val]
    if isinstance(val, dict):
        return {_strip_quotes(k): _clean_value(v)
                for k, v in val.items()
                if k != '__is_block__'}
    return val


# Sentinel to distinguish "no default" from default=null
_REQUIRED = object()


def parse_module(module_dir: Path):
    """Parse all .tf files in a directory and return an aggregated summary."""
    summary = {
        'path': module_dir,
        'files': [],
        'variables': {},        # name -> {type, description, default, sensitive, nullable}
        'outputs': {},          # name -> {description, value, sensitive}
        'resources': [],        # [{type, name}]
        'data_sources': [],     # [{type, name}]
        'sub_modules': [],      # [{name, source, version}]
        'providers': [],        # [{name, alias}]
        'required_providers': {},
        'terraform_version': None,
        'locals': [],
        'parse_errors': [],
    }

    for tf_path in sorted(module_dir.glob('*.tf')):
        summary['files'].append(tf_path.name)
        try:
            with open(tf_path, 'r', encoding='utf-8') as f:
                parsed = hcl2.load(f)
            parsed = _clean_value(parsed)
        except Exception as e:
            summary['parse_errors'].append(f"{tf_path.name}: {e}")
            continue

        for blk in parsed.get('variable', []):
            for name, attrs in blk.items():
                summary['variables'][name] = {
                    'type': _stringify(_unwrap(attrs.get('type', 'any'))) or 'any',
                    'description': _stringify(attrs.get('description')),
                    'default': attrs.get('default', _REQUIRED),
                    'sensitive': bool(attrs.get('sensitive', False)),
                    'nullable': attrs.get('nullable', True),
                }

        for blk in parsed.get('output', []):
            for name, attrs in blk.items():
                summary['outputs'][name] = {
                    'description': _stringify(attrs.get('description')),
                    'sensitive': bool(attrs.get('sensitive', False)),
                    'value': _unwrap(attrs.get('value')),
                }

        for blk in parsed.get('resource', []):
            for r_type, instances in blk.items():
                for inst_name in instances:
                    summary['resources'].append({'type': r_type, 'name': inst_name})

        for blk in parsed.get('data', []):
            for d_type, instances in blk.items():
                for inst_name in instances:
                    summary['data_sources'].append({'type': d_type, 'name': inst_name})

        for blk in parsed.get('module', []):
            for name, attrs in blk.items():
                summary['sub_modules'].append({
                    'name': name,
                    'source': _stringify(attrs.get('source', 'unknown')) or 'unknown',
                    'version': _stringify(attrs.get('version')) or None,
                })

        for blk in parsed.get('provider', []):
            for name, attrs in blk.items():
                summary['providers'].append({
                    'name': name,
                    'alias': _stringify(attrs.get('alias')) or None,
                })

        for blk in parsed.get('terraform', []):
            if 'required_version' in blk:
                summary['terraform_version'] = _stringify(blk['required_version'])
            if 'required_providers' in blk:
                rp = blk['required_providers']
                if isinstance(rp, list):
                    for item in rp:
                        if isinstance(item, dict):
                            summary['required_providers'].update(item)
                elif isinstance(rp, dict):
                    summary['required_providers'].update(rp)

        for blk in parsed.get('locals', []):
            if isinstance(blk, dict):
                for name in blk:
                    if name not in summary['locals']:
                        summary['locals'].append(name)

    return summary


# ---------- description / readme ----------

def read_description(module_dir: Path):
    """Return the contents of a README in the module directory, if any."""
    for candidate in ['README.md', 'readme.md', 'README.MD', 'README.txt', 'README']:
        p = module_dir / candidate
        if p.exists():
            try:
                return p.read_text(encoding='utf-8').strip()
            except Exception:
                continue
    return None


def extract_top_comment(module_dir: Path):
    """Pull leading # / // comments from main.tf as a fallback description."""
    candidates = [module_dir / 'main.tf'] + sorted(module_dir.glob('*.tf'))
    seen = set()
    for f in candidates:
        if f in seen or not f.exists():
            continue
        seen.add(f)
        try:
            lines = f.read_text(encoding='utf-8').splitlines()
        except Exception:
            continue
        comment_lines = []
        for line in lines:
            stripped = line.strip()
            if not stripped:
                if comment_lines:
                    break
                continue
            if stripped.startswith('#') or stripped.startswith('//'):
                comment_lines.append(re.sub(r'^[#/]+\s?', '', stripped))
            else:
                break
        if comment_lines:
            return '\n'.join(comment_lines)
    return None


# ---------- usage example generation ----------

def format_default_value(val):
    """Render a default value as a Terraform literal."""
    if val is _REQUIRED:
        return ''
    if val is None:
        return 'null'
    if isinstance(val, bool):
        return 'true' if val else 'false'
    if isinstance(val, (int, float)):
        return str(val)
    if isinstance(val, str):
        unwrapped = _unwrap(val)
        if unwrapped != val:
            return unwrapped  # interpolated expression
        return json.dumps(val)
    if isinstance(val, (list, dict)):
        try:
            return json.dumps(val)
        except (TypeError, ValueError):
            return str(val)
    return str(val)


def placeholder_for_type(t):
    """Best-guess placeholder value for a given type expression."""
    s = (t or 'any').lower()
    if 'string' in s:
        return '"..."'
    if 'number' in s:
        return '0'
    if 'bool' in s:
        return 'false'
    if 'list' in s or 'set' in s or 'tuple' in s:
        return '[]'
    if 'map' in s or 'object' in s:
        return '{}'
    return '""'


def generate_usage(module_name: str, summary: dict):
    """Produce a Terraform module-block example, required vars first."""
    required = [(n, v) for n, v in summary['variables'].items() if v['default'] is _REQUIRED]
    optional = [(n, v) for n, v in summary['variables'].items() if v['default'] is not _REQUIRED]

    # Use just the leaf directory name for the source path — the user can adjust.
    source = f'./{summary["path"].name}'
    safe_name = re.sub(r'[^a-zA-Z0-9_]', '_', module_name)

    lines = [f'module "{safe_name}" {{', f'  source = "{source}"', '']

    if required:
        lines.append('  # Required')
        max_len = max(len(n) for n, _ in required)
        for name, var in required:
            lines.append(f'  {name.ljust(max_len)} = {placeholder_for_type(var["type"])}')

    if optional:
        if required:
            lines.append('')
        lines.append('  # Optional (showing defaults — override as needed)')
        max_len = max(len(n) for n, _ in optional)
        for name, var in optional:
            rendered = format_default_value(var['default']) or '""'
            # Long defaults get truncated for readability
            if len(rendered) > 60:
                rendered = rendered[:57] + '...'
            lines.append(f'  {name.ljust(max_len)} = {rendered}')

    lines.append('}')
    return '\n'.join(lines)


# ---------- mermaid diagram ----------

def safe_id(s: str, prefix: str = 'n') -> str:
    return prefix + re.sub(r'[^a-zA-Z0-9]', '_', str(s))


def generate_mermaid(module_name: str, summary: dict) -> str:
    """Render a Mermaid graph describing the module structure."""
    lines = ['graph LR']
    root = safe_id(module_name, 'M_')
    lines.append(f'    {root}["📦 {module_name}"]')
    lines.append(f'    style {root} fill:#0052cc,stroke:#003884,color:#ffffff')

    # Group resources by type so the diagram doesn't explode
    by_type = {}
    for r in summary['resources']:
        by_type.setdefault(r['type'], []).append(r['name'])

    for r_type, names in sorted(by_type.items()):
        tid = safe_id(r_type, 'T_')
        if len(names) == 1:
            label = f"{r_type}.{names[0]}"
        else:
            label = f"{r_type}<br/>(×{len(names)})"
        lines.append(f'    {tid}["{label}"]')
        lines.append(f'    {root} --> {tid}')
        lines.append(f'    style {tid} fill:#deebff,stroke:#0052cc')

    for sub in summary['sub_modules']:
        sid = safe_id('mod_' + sub['name'], 'S_')
        lines.append(f'    {sid}(["module: {sub["name"]}"])')
        lines.append(f'    {root} --> {sid}')
        lines.append(f'    style {sid} fill:#fff0b3,stroke:#974f0c')

    if summary['data_sources']:
        did = safe_id('data', 'D_')
        ds_preview = '<br/>'.join(f"{d['type']}.{d['name']}" for d in summary['data_sources'][:4])
        if len(summary['data_sources']) > 4:
            ds_preview += f"<br/>... +{len(summary['data_sources']) - 4} more"
        lines.append(f'    {did}[("data sources<br/>{ds_preview}")]')
        lines.append(f'    {root} -.-> {did}')
        lines.append(f'    style {did} fill:#e3fcef,stroke:#006644')

    return '\n'.join(lines)


# ---------- HTML rendering ----------

CSS = """
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
  color: #172b4d;
  max-width: 1100px;
  margin: 2em auto;
  padding: 0 1.2em;
  line-height: 1.55;
}
h1 { border-bottom: 3px solid #0052cc; padding-bottom: .3em; }
h2 { border-bottom: 1px solid #dfe1e6; padding-bottom: .25em; margin-top: 2.6em; color: #0052cc; }
h3 { margin-top: 1.8em; color: #253858; font-size: 1.05em; }
table { border-collapse: collapse; width: 100%; margin: .9em 0 1.4em; font-size: 0.93em; }
th, td { border: 1px solid #dfe1e6; padding: 8px 12px; text-align: left; vertical-align: top; }
th { background: #f4f5f7; font-weight: 600; }
tr:nth-child(even) td { background: #fafbfc; }
code, pre { font-family: "SF Mono", Monaco, Consolas, "Liberation Mono", monospace; }
code { background: #f4f5f7; padding: 1px 6px; border-radius: 3px; font-size: 0.9em; }
pre { background: #1f2937; color: #e5e7eb; padding: 14px 16px; border-radius: 4px;
      overflow-x: auto; font-size: 0.85em; line-height: 1.45; }
pre code { background: transparent; color: inherit; padding: 0; }
.tag { display: inline-block; padding: 2px 8px; border-radius: 3px; font-size: 0.78em;
       font-weight: 600; white-space: nowrap; }
.tag-required  { background: #ffebe6; color: #bf2600; }
.tag-optional  { background: #e3fcef; color: #006644; }
.tag-sensitive { background: #fff0b3; color: #974f0c; }
.toc { background: #f4f5f7; padding: 1em 1.5em; border-radius: 4px; }
.toc ul { margin: .3em 0; padding-left: 1.2em; }
.toc li { margin: .15em 0; }
.meta { color: #6b778c; font-size: 0.9em; }
.empty { color: #6b778c; font-style: italic; }
.module-section { padding: 1em 0; }
.module-path { font-family: monospace; background: #f4f5f7; padding: 2px 8px;
               border-radius: 3px; font-size: 0.9em; }
.mermaid { background: #fafbfc; padding: 1em; border: 1px solid #dfe1e6;
           border-radius: 4px; text-align: center; }
details > summary { cursor: pointer; color: #0052cc; margin: .5em 0; font-size: 0.9em; }
"""


MERMAID_SCRIPT = """
<script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
<script>
  if (window.mermaid) {
    mermaid.initialize({ startOnLoad: true, theme: 'default', securityLevel: 'loose' });
  }
</script>
"""


def render_default_cell(val):
    if val is _REQUIRED:
        return '<span class="tag tag-required">required</span>'
    rendered = format_default_value(val)
    if len(rendered) > 80:
        rendered = rendered[:77] + '...'
    return f'<code>{escape(rendered)}</code>'


def _markdownish(text: str) -> str:
    """Very light Markdown-ish rendering for README text — paragraphs + code fences."""
    out = []
    in_code = False
    code_buf = []
    for line in text.splitlines():
        if line.strip().startswith('```'):
            if in_code:
                out.append('<pre><code>' + escape('\n'.join(code_buf)) + '</code></pre>')
                code_buf = []
                in_code = False
            else:
                in_code = True
            continue
        if in_code:
            code_buf.append(line)
            continue
        out.append(line)
    if in_code and code_buf:
        out.append('<pre><code>' + escape('\n'.join(code_buf)) + '</code></pre>')

    # paragraph-split the non-code chunks
    html_parts = []
    para = []
    for line in out:
        if line.startswith('<pre>'):
            if para:
                html_parts.append('<p>' + '<br/>'.join(escape(p) for p in para) + '</p>')
                para = []
            html_parts.append(line)
        elif line.strip() == '':
            if para:
                html_parts.append('<p>' + '<br/>'.join(escape(p) for p in para) + '</p>')
                para = []
        else:
            para.append(line)
    if para:
        html_parts.append('<p>' + '<br/>'.join(escape(p) for p in para) + '</p>')
    return '\n'.join(html_parts)


def render_module_section(name: str, summary: dict, root_path: Path) -> str:
    parts = []
    rel = summary['path'].relative_to(root_path) if summary['path'] != root_path else Path('.')
    rel_str = './' + str(rel) if str(rel) != '.' else '(repo root)'
    anchor = safe_id(name, 'mod-')

    parts.append(f'<section class="module-section" id="{escape(anchor)}">')
    parts.append(f'<h2>{escape(name)}</h2>')
    parts.append(f'<p class="meta">Path: <span class="module-path">{escape(rel_str)}</span></p>')

    # ---- Description
    parts.append('<h3>Description</h3>')
    desc = read_description(summary['path']) or extract_top_comment(summary['path'])
    if desc:
        parts.append(_markdownish(desc))
    else:
        parts.append(
            '<p class="empty">No README.md or top-of-file comment found. '
            'Add one to populate this section automatically next time.</p>'
        )

    # ---- Usage
    parts.append('<h3>Usage</h3>')
    parts.append(f'<pre><code>{escape(generate_usage(name, summary))}</code></pre>')

    # ---- Inputs
    parts.append('<h3>Inputs</h3>')
    if summary['variables']:
        parts.append(
            '<table><thead><tr>'
            '<th>Name</th><th>Type</th><th>Description</th>'
            '<th>Default</th><th>Flags</th>'
            '</tr></thead><tbody>'
        )
        for vname in sorted(summary['variables'].keys()):
            v = summary['variables'][vname]
            flags = []
            if v['sensitive']:
                flags.append('<span class="tag tag-sensitive">sensitive</span>')
            parts.append(
                '<tr>'
                f'<td><code>{escape(vname)}</code></td>'
                f'<td><code>{escape(v["type"])}</code></td>'
                f'<td>{escape(v["description"]) if v["description"] else "—"}</td>'
                f'<td>{render_default_cell(v["default"])}</td>'
                f'<td>{" ".join(flags) if flags else ""}</td>'
                '</tr>'
            )
        parts.append('</tbody></table>')
    else:
        parts.append('<p class="empty">No input variables defined.</p>')

    # ---- Outputs
    parts.append('<h3>Outputs</h3>')
    if summary['outputs']:
        parts.append(
            '<table><thead><tr>'
            '<th>Name</th><th>Description</th><th>Flags</th>'
            '</tr></thead><tbody>'
        )
        for oname in sorted(summary['outputs'].keys()):
            o = summary['outputs'][oname]
            flags = '<span class="tag tag-sensitive">sensitive</span>' if o['sensitive'] else ''
            parts.append(
                '<tr>'
                f'<td><code>{escape(oname)}</code></td>'
                f'<td>{escape(o["description"]) if o["description"] else "—"}</td>'
                f'<td>{flags}</td>'
                '</tr>'
            )
        parts.append('</tbody></table>')
    else:
        parts.append('<p class="empty">No outputs defined.</p>')

    # ---- Managed resources
    parts.append('<h3>Managed resources</h3>')
    if summary['resources']:
        parts.append('<table><thead><tr><th>Type</th><th>Name</th></tr></thead><tbody>')
        for r in sorted(summary['resources'], key=lambda r: (r['type'], r['name'])):
            parts.append(
                f'<tr><td><code>{escape(r["type"])}</code></td>'
                f'<td><code>{escape(r["name"])}</code></td></tr>'
            )
        parts.append('</tbody></table>')
    else:
        parts.append('<p class="empty">No managed resources.</p>')

    # ---- Data sources
    if summary['data_sources']:
        parts.append('<h3>Data sources</h3>')
        parts.append('<table><thead><tr><th>Type</th><th>Name</th></tr></thead><tbody>')
        for d in sorted(summary['data_sources'], key=lambda d: (d['type'], d['name'])):
            parts.append(
                f'<tr><td><code>{escape(d["type"])}</code></td>'
                f'<td><code>{escape(d["name"])}</code></td></tr>'
            )
        parts.append('</tbody></table>')

    # ---- Sub-modules
    if summary['sub_modules']:
        parts.append('<h3>Sub-modules used</h3>')
        parts.append(
            '<table><thead><tr><th>Name</th><th>Source</th><th>Version</th></tr></thead><tbody>'
        )
        for m in summary['sub_modules']:
            parts.append(
                '<tr>'
                f'<td><code>{escape(m["name"])}</code></td>'
                f'<td><code>{escape(m["source"])}</code></td>'
                f'<td>{escape(m["version"]) if m["version"] else "—"}</td>'
                '</tr>'
            )
        parts.append('</tbody></table>')

    # ---- Required providers
    if summary['required_providers']:
        parts.append('<h3>Required providers</h3>')
        parts.append(
            '<table><thead><tr><th>Name</th><th>Source</th><th>Version</th></tr></thead><tbody>'
        )
        for pname, pinfo in summary['required_providers'].items():
            if isinstance(pinfo, dict):
                src = _stringify(pinfo.get('source')) or '—'
                ver = _stringify(pinfo.get('version')) or '—'
            else:
                src, ver = '—', _stringify(pinfo) or '—'
            parts.append(
                '<tr>'
                f'<td><code>{escape(pname)}</code></td>'
                f'<td><code>{escape(src)}</code></td>'
                f'<td><code>{escape(ver)}</code></td>'
                '</tr>'
            )
        parts.append('</tbody></table>')

    if summary['terraform_version']:
        parts.append(
            f'<p class="meta">Required Terraform version: '
            f'<code>{escape(summary["terraform_version"])}</code></p>'
        )

    # ---- Diagram
    parts.append('<h3>Diagram</h3>')
    mermaid_code = generate_mermaid(name, summary)
    parts.append(f'<div class="mermaid">\n{mermaid_code}\n</div>')
    parts.append(
        '<details><summary>Mermaid source — copy into a Confluence Mermaid macro</summary>'
        f'<pre><code>{escape(mermaid_code)}</code></pre></details>'
    )

    # ---- Parse warnings
    if summary['parse_errors']:
        parts.append('<h3>Parse warnings</h3><ul>')
        for err in summary['parse_errors']:
            parts.append(f'<li><code>{escape(err)}</code></li>')
        parts.append('</ul>')

    # ---- File listing
    if summary['files']:
        files_html = ', '.join(f'<code>{escape(f)}</code>' for f in summary['files'])
        parts.append(f'<p class="meta">Source files: {files_html}</p>')

    parts.append('</section>')
    return '\n'.join(parts)


def render_html(modules, root_path: Path, title: str) -> str:
    parts = [
        '<!DOCTYPE html>', '<html lang="en">', '<head>',
        '<meta charset="utf-8">',
        '<meta name="viewport" content="width=device-width, initial-scale=1">',
        f'<title>{escape(title)}</title>',
        f'<style>{CSS}</style>',
        '</head><body>',
    ]
    parts.append(f'<h1>{escape(title)}</h1>')
    parts.append(
        f'<p class="meta">Generated {datetime.now().strftime("%Y-%m-%d %H:%M")} '
        f'from <code>{escape(str(root_path))}</code> · '
        f'{len(modules)} module(s)</p>'
    )

    parts.append('<div class="toc"><strong>Modules</strong><ul>')
    for name, summary in modules:
        anchor = safe_id(name, 'mod-')
        counts = (
            f'{len(summary["variables"])} inputs · '
            f'{len(summary["outputs"])} outputs · '
            f'{len(summary["resources"])} resources'
        )
        parts.append(
            f'<li><a href="#{escape(anchor)}">{escape(name)}</a> '
            f'<span class="meta">— {counts}</span></li>'
        )
    parts.append('</ul></div>')

    for name, summary in modules:
        parts.append(render_module_section(name, summary, root_path))

    parts.append(MERMAID_SCRIPT)
    parts.append('</body></html>')
    return '\n'.join(parts)


# ---------- main ----------

def derive_module_name(module_dir: Path, root_path: Path) -> str:
    if module_dir == root_path:
        return root_path.name or 'root'
    rel = module_dir.relative_to(root_path)
    return str(rel).replace(os.sep, '/')


def main():
    ap = argparse.ArgumentParser(
        description='Generate HTML documentation from Terraform module directories.',
    )
    ap.add_argument('path', nargs='?', default='.',
                    help='Directory to scan (default: current directory).')
    ap.add_argument('-o', '--output', default='terraform-docs.html',
                    help='Output HTML file (default: terraform-docs.html).')
    ap.add_argument('--title', help='Report title (default: derived from directory name).')
    args = ap.parse_args()

    root = Path(args.path).resolve()
    if not root.exists():
        sys.exit(f'Path does not exist: {root}')

    title = args.title or f'Terraform modules — {root.name}'

    print(f'Scanning {root}…')
    module_dirs = find_module_dirs(root)
    if not module_dirs:
        sys.exit('No directories with .tf files found.')

    modules = []
    for d in module_dirs:
        name = derive_module_name(d, root)
        print(f'  · parsing {name}')
        summary = parse_module(d)
        modules.append((name, summary))

    html = render_html(modules, root, title)
    out = Path(args.output)
    out.write_text(html, encoding='utf-8')
    print(f'\nWrote {out.resolve()}  ({len(modules)} module(s))')


if __name__ == '__main__':
    main()
