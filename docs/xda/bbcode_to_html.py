#!/usr/bin/env python3
"""docs/XDA-POST.md (BB code between the ---- lines) -> docs/xda/post.html: open it in a browser, select all, copy and
paste into XDA's normal (rich text) editor, formatting included. The image spots and the spoiler stay as marked text."""
import html
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, "..", "XDA-POST.md")).read()
bb = src.split("-" * 118)[1].strip()

h = html.escape(bb, quote=False)
h = re.sub(r"\[ATTACH type=\"full\"\](\w+)\[/ATTACH\]",
           lambda m: f'<p class="todo">&#9654; insert image here: {m.group(1).lower()}.png (Upload &gt; Full image)</p>', h)
h = re.sub(r'\[SPOILER="([^"]+)"\]\s*(.*?)\s*\[/SPOILER\]',
           lambda m: f'<p>[SPOILER="{m.group(1)}"]</p>{m.group(2)}<p>[/SPOILER]</p>', h, flags=re.S)
h = re.sub(r"\[SIZE=5\]\[B\](.*?)\[/B\]\[/SIZE\]", r"<h2>\1</h2>", h)
h = re.sub(r"\[B\](.*?)\[/B\]", r"<b>\1</b>", h, flags=re.S)
h = re.sub(r"\[ICODE\](.*?)\[/ICODE\]", r"<code>\1</code>", h)
h = re.sub(r"\[COLOR=([^\]]+)\](.*?)\[/COLOR\]", r'<span style="color:\1">\2</span>', h, flags=re.S)
h = re.sub(r"\[URL='([^']+)'\](.*?)\[/URL\]", r'<a href="\1">\2</a>', h)


def lists(t):
    def one(m):
        tag = "ol" if m.group(1) else "ul"
        items = [i.strip().replace("\n", "<br>") for i in m.group(2).split("[*]") if i.strip()]
        return f"<{tag}>" + "".join(f"<li>{i}</li>" for i in items) + f"</{tag}>"
    while "[LIST" in t:
        t = re.sub(r"\[LIST(=1)?\]((?:(?!\[LIST).)*?)\[/LIST\]", one, t, flags=re.S)
    return t


h = lists(h)
blocks = [b.strip() for b in re.split(r"\n\s*\n", h) if b.strip()]
body = "\n".join(b if b.startswith(("<h2", "<ul", "<ol", "<p")) or "</h2>" in b[:200] and b.startswith("<h2")
                 else "<p>" + b.replace("\n", "<br>") for b in blocks)
body = re.sub(r"(</h2>)<br>", r"\1", body.replace("</h2>\n", "</h2>"))
page = f"""<!doctype html><html><head><meta charset="utf-8"><title>XDA post</title>
<style>body{{font:15px/1.5 -apple-system,Segoe UI,sans-serif;max-width:820px;margin:32px auto;padding:0 16px}}
h2{{font-size:20px;margin:22px 0 6px}} code{{background:#eee;padding:1px 4px;border-radius:3px}}
.todo{{background:#fff3c4;border:1px dashed #c9a400;padding:6px 10px}}</style></head><body>
{body}
</body></html>"""
open(os.path.join(HERE, "post.html"), "w").write(page)
print("wrote", os.path.join(HERE, "post.html"))
