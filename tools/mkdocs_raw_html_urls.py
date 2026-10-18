"""MkDocs hook: resolve the asset paths written in raw HTML.

MkDocs rewrites a Markdown image for the page's published URL, so
`![](images/x.png)` on features.md becomes `../images/x.png` on /features/. It
leaves raw HTML alone. The pages use raw `<img>` and `<picture>` where they need
a width or a light and dark pair that also renders on GitHub, and every one of
those resolved against /features/ or /brand/BRAND/ instead of the source file,
so the published site showed alt text where the pictures should be.

This hook reads src, srcset and poster on img, source, video and audio tags. A
path that already resolves against the published page is left alone, which is
what MkDocs produced from Markdown. One that resolves against the source file
is rewritten to reach the same file from the published page. One that resolves
against neither is a warning, so `mkdocs build --strict` fails on it rather than
publishing a broken picture.
"""

from __future__ import annotations

import logging
import posixpath
import re

log = logging.getLogger(f"mkdocs.hooks.{__name__}")

_TAG = re.compile(r"<(?:img|source|video|audio)\b[^>]*>", re.IGNORECASE)
_ATTR = re.compile(r'(\s(?:src|srcset|poster)=")([^"]*)(")', re.IGNORECASE)
_EXTERNAL = re.compile(r"^(?:[a-z][a-z0-9+.-]*:|//|/|#)", re.IGNORECASE)


def _split(url: str) -> tuple[str, str]:
    """Separate a path from its query or fragment, such as `#only-light`."""
    match = re.search(r"[?#]", url)
    if match is None:
        return url, ""
    return url[: match.start()], url[match.start() :]


def _resolve(url: str, page, files, published: set[str]) -> str:
    if not url or _EXTERNAL.match(url):
        return url
    path, tail = _split(url)
    # features/ publishes from features.md; a page without directory URLs
    # publishes as features.html beside it.
    url_dir = page.url[:-1] if page.url.endswith("/") else posixpath.dirname(page.url)
    if posixpath.normpath(posixpath.join(url_dir, path)) in published:
        return url
    source = posixpath.normpath(
        posixpath.join(posixpath.dirname(page.file.src_uri), path)
    )
    target = files.get_file_from_path(source)
    if target is None:
        log.warning(
            "Raw HTML in '%s' points at '%s', which is not in the docs.",
            page.file.src_uri,
            url,
        )
        return url
    return posixpath.relpath(target.url, url_dir or ".") + tail


def _rewrite_srcset(value: str, page, files, published: set[str]) -> str:
    candidates = []
    for candidate in value.split(","):
        parts = candidate.strip().split(None, 1)
        if not parts:
            continue
        parts[0] = _resolve(parts[0], page, files, published)
        candidates.append(" ".join(parts))
    return ", ".join(candidates)


def on_page_content(html, page, config, files):
    published = {f.url for f in files}

    def tag(match: re.Match) -> str:
        def attr(found: re.Match) -> str:
            name = found.group(1).strip().lower()
            value = found.group(2)
            if name.startswith("srcset"):
                value = _rewrite_srcset(value, page, files, published)
            else:
                value = _resolve(value, page, files, published)
            return found.group(1) + value + found.group(3)

        return _ATTR.sub(attr, match.group(0))

    return _TAG.sub(tag, html)
