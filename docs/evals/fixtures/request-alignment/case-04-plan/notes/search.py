"""Linear text search over notes."""


def find(notes, text):
    needle = text.lower()
    return [note for note in notes if needle in note["text"].lower()]
