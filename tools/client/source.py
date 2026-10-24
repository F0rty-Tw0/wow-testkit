"""What a writer reads from: install paths (lowercase, '/') over a CascStore plus the listfile names."""

from typing import Iterable, Optional, Protocol


class Source(Protocol):
    locales: list

    def paths(self) -> Iterable[str]: ...

    def read(self, path: str, partial: bool = False) -> Optional[bytes]: ...

    def file_id(self, path: str) -> Optional[int]: ...


class CascSource:
    """Source over a CascStore and {fileID: path}; only names whose file the store holds are visible.
    `partial` is forwarded to the store: only DB2 writers pass it (see casc.CascStore.read)."""

    def __init__(self, store, names, locales):
        present = set(store.file_ids())
        self.store = store
        self.locales = list(locales)
        self.ids = {}
        for file_id in sorted(present.intersection(names)):
            self.ids.setdefault(names[file_id], file_id)

    def paths(self):
        return sorted(self.ids)

    def file_id(self, path):
        return self.ids.get(path.replace("\\", "/").lower())

    def read(self, path, partial=False):
        file_id = self.file_id(path)
        return None if file_id is None else self.store.read(file_id, partial=partial)
