"""Generate the PLCopen XML for CODESYS from the ST sources in ``Source/``.

    python st_to_plcopen.py            -> SRCI_TcpIp_Bridge.xml (next to this script)

CODESYS: select the project, Project -> Import PLCopenXML... The file has the form of a PLCopen export
of CODESYS V3.5 SP22: the objects lie in the Application (GVL, PLC_PRG, folder "Bridge" with the FB and
its method), the declarations are the structured PLCopen interface with the ``///`` comments as
documentation. Only the small subset of ST declarations used in ``Source/`` is supported (one
variable per line).
The object IDs are derived from the names, so the file only changes when the sources change.
"""

from __future__ import annotations

import re
import sys
import uuid
from pathlib import Path
from xml.sax.saxutils import escape

HERE = Path(__file__).resolve().parent
SOURCE = HERE / "Source"
OUTPUT = HERE / "SRCI_TcpIp_Bridge.xml"
STAMP = "2026-10-04T00:00:00"  # fixed, so the XML only changes with the sources
XHTML = '<xhtml xmlns="http://www.w3.org/1999/xhtml">'
NS = "http://www.3s-software.com/plcopenxml/"
ELEMENTARY = {
    "BOOL", "BYTE", "WORD", "DWORD", "LWORD", "SINT", "INT", "DINT", "LINT", "USINT", "UINT", "UDINT",
    "ULINT", "REAL", "LREAL", "TIME", "LTIME", "DATE", "TOD", "DT",
}  # fmt: skip
SECTIONS = {
    "VAR_INPUT": "inputVars", "VAR_OUTPUT": "outputVars", "VAR_IN_OUT": "inOutVars", "VAR": "localVars",
    "VAR CONSTANT": "localVars constant", "VAR_GLOBAL": "globalVars",
}  # fmt: skip
DECL = re.compile(r"^\s*(\w+)\s*:\s*(.+?)\s*(?::=\s*(.+?))?\s*;\s*$")


def object_id(name: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_URL, f"srci-tcpip-bridge/{name}"))


def indent(text: str, prefix: str) -> str:
    return "\n".join(prefix + line if line else line for line in text.split("\n"))


def type_xml(text: str) -> str:
    t = text.strip()
    if m := re.fullmatch(r"(?i)(W?STRING)\s*\(\s*(\d+)\s*\)", t):
        return f'<{m.group(1).lower()} length="{m.group(2)}" />'
    if t.upper() in ("STRING", "WSTRING"):
        return f"<{t.lower()} />"
    if m := re.fullmatch(r"(?i)ARRAY\s*\[\s*([^\].]+)\s*\.\.\s*([^\]]+?)\s*\]\s*OF\s+(.+)", t):
        return (f'<array>\n  <dimension lower="{m.group(1)}" upper="{m.group(2)}" />\n  <baseType>\n'
                f"{indent(type_xml(m.group(3)), '    ')}\n  </baseType>\n</array>")  # fmt: skip
    if m := re.fullmatch(r"(?i)ARRAY\s*\[\s*\*\s*\]\s*OF\s+(.+)", t):
        return f"<pointer>\n  <baseType>\n{indent(type_xml(m.group(1)), '    ')}\n  </baseType>\n</pointer>"
    if t.upper() in ELEMENTARY:
        return f"<{t.upper()} />"
    if re.fullmatch(r"\w+", t):
        return f'<derived name="{t}" />'
    raise ValueError(f"type {t!r} not supported")


def is_vla(type_text: str) -> bool:
    return bool(re.fullmatch(r"(?i)ARRAY\s*\[\s*\*\s*\]\s*OF\s+.+", type_text.strip()))


def variable_xml(name: str, type_text: str, init: str | None, doc: str, scope: str = "") -> str:
    parts = [f'<variable name="{name}">', "  <type>", indent(type_xml(type_text), "    "), "  </type>"]
    if init is not None:
        parts += ["  <initialValue>", f'    <simpleValue value="{escape(init, {chr(34): "&quot;"})}" />',
                  "  </initialValue>"]  # fmt: skip
    if is_vla(type_text):
        vla = re.sub(r"\s+", " ", type_text.strip()).upper().replace("[ * ]", "[*]")
        parts += [
            "  <addData>",
            f'    <data name="{NS}attributes" handleUnknown="implementation">',
            "      <Attributes>",
            *([f'        <Attribute Name="variable_length_array_original_scope" Value="{scope}" />'] if scope else []),
            f'        <Attribute Name="variable_length_array" Value="{escape(vla)}" />',
            '        <Attribute Name="Dimensions" Value="1" />',
            "      </Attributes>",
            "    </data>",
            "  </addData>",
        ]
    if doc:
        parts += ["  <documentation>", f"    {XHTML} {escape(doc)}</xhtml>", "  </documentation>"]
    parts.append("</variable>")
    return "\n".join(parts)


def sections_xml(declaration: str) -> list[str]:
    """``<inputVars>`` ... blocks of a declaration text. Like the PLCopen export of CODESYS, variable
    length arrays of ``VAR_IN_OUT`` are pointers in ``<inputVars>`` (original scope "Inout")."""
    out: list[str] = []
    moved: list[str] = []
    section: str | None = None
    variables: list[str] = []
    doc: list[str] = []
    for line in declaration.splitlines():
        s = line.strip()
        if not s or s.startswith("{attribute") or (s.startswith("//") and not s.startswith("///")):
            continue
        key = re.sub(r"\s+", " ", s.upper())
        if key in SECTIONS:
            section, variables, doc = SECTIONS[key], [], []
        elif key == "END_VAR":
            assert section is not None
            tag, _, constant = section.partition(" ")
            head = f'<{tag} constant="true">' if constant else f"<{tag}>"
            if variables:
                out.append(f"{head}\n{indent(chr(10).join(variables), '  ')}\n</{tag}>")
            section = None
        elif s.startswith("///"):
            doc.append(s[3:].strip())
        elif section is not None and (m := DECL.match(s)):
            if section == "inOutVars" and is_vla(m.group(2)):
                moved.append(variable_xml(m.group(1), m.group(2), m.group(3), " ".join(doc), "Inout"))
            else:
                variables.append(variable_xml(m.group(1), m.group(2), m.group(3), " ".join(doc)))
            doc = []
        elif section is not None:
            raise ValueError(f"declaration line {s!r} not supported")
    if moved:
        inputs = [i for i, block in enumerate(out) if block.startswith("<inputVars>")]
        if inputs:
            block = out[inputs[0]]
            out[inputs[0]] = block[: -len("</inputVars>")] + indent("\n".join(moved), "  ") + "\n</inputVars>"
        else:
            out.insert(0, f"<inputVars>\n{indent(chr(10).join(moved), '  ')}\n</inputVars>")
    return out


def split_pou(text: str) -> tuple[str, str, str, str, list[tuple[str, str, str, str]]]:
    """(kind, name, declaration, body, methods) of a POU file; methods: (name, return, decl, body)."""
    end = re.search(r"^END_(FUNCTION_BLOCK|PROGRAM)\s*$", text, flags=re.M)
    assert end, "END_FUNCTION_BLOCK / END_PROGRAM missing"
    main, rest = text[: end.start()], text[end.end() :]
    head = re.search(r"^(FUNCTION_BLOCK|PROGRAM)\s+(\w+)", main, flags=re.M)
    assert head
    last_var = list(re.finditer(r"^END_VAR\s*$", main, flags=re.M))[-1]
    declaration, body = main[: last_var.end()], main[last_var.end() :]
    methods = []
    for m in re.finditer(r"^((?:///[^\n]*\n)*)METHOD\s+(\w+)\s*:\s*(\w+)(.*?)^END_METHOD\s*$", rest, flags=re.M | re.S):
        inner = f"{m.group(1)}METHOD {m.group(2)} : {m.group(3)}{m.group(4)}"
        mv = list(re.finditer(r"^END_VAR\s*$", inner, flags=re.M))[-1]
        methods.append((m.group(2), m.group(3), inner[: mv.end()], inner[mv.end() :]))
    return head.group(1), head.group(2), declaration, strip_body(body), methods


def strip_body(body: str) -> str:
    """Body text without the empty lines around it (indentation kept, like the export)."""
    lines = body.strip("\n").split("\n")
    while lines and not lines[-1].strip():
        lines.pop()
    return "\n".join(lines)


def documentation(declaration: str) -> str:
    """``///`` line above the header and the header comment (``// ...``) of a declaration."""
    lines = []
    for line in declaration.splitlines():
        s = line.strip()
        if s.startswith("///"):
            lines.append(s[3:].strip())
        elif s.startswith("//"):
            lines.append(s[2:].rstrip())
        elif re.match(r"(?i)VAR", s):
            break
    return "\n".join(lines).strip("\n")


def doc_xml(text: str) -> str:
    return f"<documentation>\n  {XHTML}{escape(text)}</xhtml>\n</documentation>" if text else ""


def pou_xml(path: Path) -> tuple[str, str, list[str]]:
    """(name, ``<pou>`` element, names of the methods)."""
    kind, name, declaration, body, methods = split_pou(path.read_text(encoding="utf-8"))
    pou_type = "functionBlock" if kind == "FUNCTION_BLOCK" else "program"
    interface = "\n".join(x for x in [*sections_xml(declaration), doc_xml(documentation(declaration))] if x)
    add = []
    for m_name, m_return, m_decl, m_body in methods:
        m_itf = "\n".join(
            x
            for x in [f"<returnType>\n  {type_xml(m_return)}\n</returnType>", *sections_xml(m_decl),
                      doc_xml(documentation(m_decl))]
            if x
        )  # fmt: skip
        method = (
            f'<Method name="{m_name}" ObjectId="{object_id(name + "." + m_name)}">\n'
            f"  <interface>\n{indent(m_itf, '    ')}\n  </interface>\n"
            f"  <body>\n    <ST>\n      {XHTML}{escape(strip_body(m_body))}</xhtml>\n    </ST>\n  </body>\n"
            "  <addData />\n</Method>"
        )
        add.append(f'<data name="{NS}method" handleUnknown="implementation">\n{indent(method, "  ")}\n</data>')
    add.append(f'<data name="{NS}objectid" handleUnknown="discard">\n  <ObjectId>{object_id(name)}</ObjectId>\n</data>')
    xml = (
        f'<pou name="{name}" pouType="{pou_type}">\n'
        f"  <interface>\n{indent(interface, '    ')}\n  </interface>\n"
        f"  <body>\n    <ST>\n      {XHTML}{escape(body)}</xhtml>\n    </ST>\n  </body>\n"
        f"  <addData>\n{indent(chr(10).join(add), '    ')}\n  </addData>\n</pou>"
    )
    return name, xml, [m[0] for m in methods]


def gvl_xml(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    name = path.stem
    (block,) = sections_xml(text)
    inner = block.split("\n", 1)[1].rsplit("\n", 1)[0]
    attrs = re.findall(r"\{attribute '(\w+)'\}", text)
    add = []
    if attrs:
        items = "\n".join(f'      <Attribute Name="{a}" Value="" />' for a in attrs)
        add.append(f'<data name="{NS}attributes" handleUnknown="implementation">\n'
                   f"  <Attributes>\n{items}\n  </Attributes>\n</data>")  # fmt: skip
    add.append(f'<data name="{NS}objectid" handleUnknown="discard">\n  <ObjectId>{object_id(name)}</ObjectId>\n</data>')
    return (f'<globalVars name="{name}">\n{inner}\n  <addData>\n{indent(chr(10).join(add), "    ")}\n'
            f"  </addData>\n{indent(doc_xml(documentation(text)), '  ')}\n</globalVars>")  # fmt: skip


def project_xml() -> str:
    """The objects in the Application, as in a PLCopen export of CODESYS (V3.5 SP22): global
    variable lists directly in ``<resource name="Application">``, POUs in its ``addData``."""
    pou_files = [p for p in sorted(SOURCE.glob("*.st")) if not p.stem.startswith("GVL_")]
    gvl_files = sorted(SOURCE.glob("GVL_*.st"))
    pous = [pou_xml(p) for p in pou_files]
    gvls = [gvl_xml(p) for p in gvl_files]
    pou_data = "\n".join(
        f'<data name="{NS}pou" handleUnknown="implementation">\n{indent(xml, "  ")}\n</data>' for _, xml, _ in pous
    )
    application = (
        '<resource name="Application">\n'
        + indent("\n".join(gvls), "  ")
        + f"\n  <addData>\n{indent(pou_data, '    ')}\n"
        + f'    <data name="{NS}objectid" handleUnknown="discard">\n'
        + f"      <ObjectId>{object_id('Application')}</ObjectId>\n    </data>\n  </addData>\n</resource>"
    )

    # project tree: PLC_PRG and the GVL in the Application, the bridge FB (with its methods) in "Bridge"
    def obj(name: str, methods: list[str]) -> list[str]:
        if not methods:
            return [f'<Object Name="{name}" ObjectId="{object_id(name)}" />']
        children = [f'  <Object Name="{m}" ObjectId="{object_id(name + "." + m)}" />' for m in methods]
        return [f'<Object Name="{name}" ObjectId="{object_id(name)}">', *children, "</Object>"]

    tree: list[str] = []
    for name, _, methods in pous:
        if name == "PLC_PRG":
            tree += obj(name, methods)
    tree += [f'<Object Name="{p.stem}" ObjectId="{object_id(p.stem)}" />' for p in gvl_files]
    tree.append('<Folder Name="Bridge">')
    for name, _, methods in pous:
        if name != "PLC_PRG":
            tree += [f"  {line}" for line in obj(name, methods)]
    tree.append("</Folder>")
    structure = [f'<Object Name="Application" ObjectId="{object_id("Application")}">', *[f"  {t}" for t in tree],
                 "</Object>"]  # fmt: skip
    now = STAMP
    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<project xmlns="http://www.plcopen.org/xml/tc6_0200">\n'
        f'  <fileHeader companyName="" productName="CODESYS" productVersion="CODESYS V3.5 SP22 Patch 2" creationDateTime="{now}" />\n'
        f'  <contentHeader name="SRCI_TcpIp_Bridge.project" modificationDateTime="{now}">\n'
        "    <coordinateInfo>\n"
        '      <fbd>\n        <scaling x="1" y="1" />\n      </fbd>\n'
        '      <ld>\n        <scaling x="1" y="1" />\n      </ld>\n'
        '      <sfc>\n        <scaling x="1" y="1" />\n      </sfc>\n'
        "    </coordinateInfo>\n"
        f'    <addData>\n      <data name="{NS}projectinformation" handleUnknown="implementation">\n'
        "        <ProjectInformation />\n      </data>\n    </addData>\n  </contentHeader>\n"
        "  <types>\n    <dataTypes />\n    <pous />\n  </types>\n"
        "  <instances>\n    <configurations />\n  </instances>\n"
        "  <addData>\n"
        f'    <data name="{NS}application" handleUnknown="implementation">\n{indent(application, "      ")}\n    </data>\n'
        f'    <data name="{NS}projectstructure" handleUnknown="discard">\n      <ProjectStructure>\n'
        + indent("\n".join(structure), "        ")
        + "\n      </ProjectStructure>\n    </data>\n  </addData>\n</project>\n"
    )


def main() -> int:
    OUTPUT.write_text(project_xml(), encoding="utf-8-sig")  # with BOM, like the export
    print(f"-> {OUTPUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
