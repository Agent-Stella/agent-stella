#!/usr/bin/env python3
"""Standalone document parser for stella-rag-go.
Usage: python3 stella_parse.py --file <path> --type pdf|docx|pptx
Output: JSON to stdout: {"text": "extracted text content"}
"""

import argparse
import json
import sys


def parse_pdf(path: str) -> str:
    try:
        import pymupdf4llm
        return pymupdf4llm.to_markdown(path)
    except ImportError:
        import fitz  # pymupdf
        doc = fitz.open(path)
        text = ""
        for page in doc:
            text += page.get_text() + "\n"
        return text


def parse_docx(path: str) -> str:
    from docx import Document
    doc = Document(path)
    lines = []
    for para in doc.paragraphs:
        if para.text.strip():
            lines.append(para.text)
    for table in doc.tables:
        for row in table.rows:
            cells = [cell.text.strip() for cell in row.cells]
            lines.append(" | ".join(cells))
    return "\n".join(lines)


def parse_pptx(path: str) -> str:
    from pptx import Presentation
    prs = Presentation(path)
    lines = []
    for i, slide in enumerate(prs.slides, 1):
        lines.append(f"## Slide {i}")
        for shape in slide.shapes:
            if hasattr(shape, "text") and shape.text.strip():
                lines.append(shape.text)
            if shape.has_table:
                for row in shape.table.rows:
                    cells = [cell.text.strip() for cell in row.cells]
                    lines.append("| " + " | ".join(cells) + " |")
        lines.append("")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", required=True, help="Path to file")
    parser.add_argument("--type", required=True, choices=["pdf", "docx", "pptx"])
    args = parser.parse_args()

    parsers = {
        "pdf": parse_pdf,
        "docx": parse_docx,
        "pptx": parse_pptx,
    }

    try:
        text = parsers[args.type](args.file)
        json.dump({"text": text}, sys.stdout)
    except Exception as e:
        json.dump({"error": str(e)}, sys.stdout)
        sys.exit(1)


if __name__ == "__main__":
    main()
