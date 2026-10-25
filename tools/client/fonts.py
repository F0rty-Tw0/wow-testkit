"""Fonts: copies fonts/*.ttf|otf out of the client and writes each one's glyph table (advance widths and kerning in
font units) to fonts/glyphs/<name>.lua, for text measurement without a font renderer."""

import io

from fontTools.ttLib import TTFont

from tools.client import paths

KERN_SHIFT = 0x200000  # above any codepoint, so left * KERN_SHIFT + right is a unique key
FONT_SUFFIXES = (".ttf", ".otf")
HORIZONTAL_KERN = 0x5  # coverage bits 1 (horizontal) and 4 (cross-stream); plain kerning has only bit 1


def codepoints_of(font):
    """{glyph name: [codepoints]} from the best cmap."""
    names = {}
    for codepoint, name in font.getBestCmap().items():
        names.setdefault(name, []).append(codepoint)
    return names


def add_pair(kern, lefts, rights, value):
    """kern[left * KERN_SHIFT + right] = value for each codepoint pair, keeping the value a pair already has."""
    if value:
        for left in lefts:
            for right in rights:
                kern.setdefault(left * KERN_SHIFT + right, value)


def legacy_kern(font, names, kern):
    for table in font["kern"].kernTables:
        pairs = getattr(table, "kernTable", None)
        if pairs and getattr(table, "coverage", 1) & HORIZONTAL_KERN == 1:
            for (left, right), value in pairs.items():
                add_pair(kern, names.get(left, ()), names.get(right, ()), value)


def pair_positions(gpos):
    """PairPos subtables of the lookups the `kern` feature names, extension lookups unwrapped, in lookup order."""
    features = [feature.Feature for feature in gpos.FeatureList.FeatureRecord if feature.FeatureTag == "kern"]
    wanted = sorted({index for feature in features for index in feature.LookupListIndex})
    for index in wanted:
        for sub in gpos.LookupList.Lookup[index].SubTable:
            sub = getattr(sub, "ExtSubTable", sub)
            if type(sub).__name__ == "PairPos":
                yield sub


def x_advance(value):
    return getattr(value, "XAdvance", 0) or 0


def class_members(class_def, glyphs):
    """{class: [glyph]} over `glyphs`; class 0 holds the glyphs class_def does not list."""
    members = {}
    for glyph in glyphs:
        members.setdefault(class_def.get(glyph, 0), []).append(glyph)
    return members


def gpos_pairs(sub, names, kern):
    covered = sub.Coverage.glyphs
    if sub.Format == 1:
        for left, pair_set in zip(covered, sub.PairSet):
            for record in pair_set.PairValueRecord:
                add_pair(kern, names.get(left, ()), names.get(record.SecondGlyph, ()), x_advance(record.Value1))
        return
    firsts = class_members(sub.ClassDef1.classDefs, covered)
    seconds = class_members(sub.ClassDef2.classDefs, names)  # class 0 of the second glyph is "any other": not expanded
    for class1, row in enumerate(sub.Class1Record):
        for class2, cell in enumerate(row.Class2Record):
            value = x_advance(cell.Value1)
            if value and class2:
                for left in firsts.get(class1, ()):
                    for right in seconds.get(class2, ()):
                        add_pair(kern, names.get(left, ()), names.get(right, ()), value)


def glyph_table(ttf):
    """{upm, notdef, advance {codepoint: units}, kern {left * KERN_SHIFT + right: units}} of a TrueType or OpenType
    font; raises on bytes fontTools cannot read. Legacy `kern` pairs come first, then GPOS `kern` feature pairs
    (formats 1 and 2); the first value a pair gets stays."""
    font = TTFont(io.BytesIO(ttf), lazy=True)
    names = codepoints_of(font)
    metrics = font["hmtx"]
    kern = {}
    if "kern" in font:
        legacy_kern(font, names, kern)
    if "GPOS" in font and font["GPOS"].table.FeatureList:
        for sub in pair_positions(font["GPOS"].table):
            gpos_pairs(sub, names, kern)
    return {
        "upm": font["head"].unitsPerEm,
        "notdef": metrics[font.getGlyphOrder()[0]][0],
        "advance": {cp: metrics[name][0] for name, cps in names.items() for cp in cps},
        "kern": kern,
    }


def lua_pairs(items):
    return "".join(f"[{key}]={value}," + ("\n" if n % 8 == 7 else "") for n, (key, value) in enumerate(items))


def to_lua(table):
    """`return { upm, notdef, advance = {[codepoint] = n}, kern = {[left * KERN_SHIFT + right] = n} }`, keys sorted."""
    advance, kern = (lua_pairs(sorted(table[key].items())) for key in ("advance", "kern"))
    head = f"return {{\nupm={table['upm']},\nnotdef={table['notdef']},\n"
    return head + f"advance={{\n{advance}\n}},\nkern={{\n{kern}\n}},\n}}\n"


def is_font(path):
    directory, _, name = path.rpartition("/")
    return directory == "fonts" and name.endswith(FONT_SUFFIXES)


def write(source, out, ctx):
    """Writes <out>/fonts/<name> and <out>/fonts/glyphs/<name>.lua for each fonts/*.ttf|otf; a file that does not
    read or parse is skipped and noted. Returns the fonts written."""
    written = 0
    for path in source.paths():
        if not is_font(path):
            continue
        rel = paths.safe_rel(path)
        if rel is None or rel.rpartition("/")[0] != "fonts":  # fonts/c:x.ttf would join to a drive-relative c:x.ttf
            ctx.notes.append(f"fonts: skipped unsafe path {path!r}")
            continue
        name = rel.rpartition("/")[2]
        data = source.read(path)
        try:
            if data is None:
                raise ValueError("unreadable")
            lua = to_lua(glyph_table(data))
        except Exception as err:  # fontTools raises many types on damaged files
            ctx.notes.append(f"fonts: {path} skipped ({type(err).__name__}: {err})")
            continue
        (out / "fonts" / "glyphs").mkdir(parents=True, exist_ok=True)
        (out / "fonts" / name).write_bytes(data)
        (out / "fonts" / "glyphs" / f"{name}.lua").write_text(lua, encoding="utf-8", newline="\n")
        written += 1
    return written
