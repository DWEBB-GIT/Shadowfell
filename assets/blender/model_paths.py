"""Keep Blender rebuilds pointed at the organised runtime model locations."""
import json
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2]


def model_output(filename):
    registry = PROJECT / 'assets/model_library.json'
    paths = json.loads(registry.read_text(encoding='utf-8'))['models'] if registry.exists() else {}
    uri = paths.get(Path(filename).stem, 'res://assets/models/' + Path(filename).name)
    destination = (PROJECT / uri.removeprefix('res://')).resolve()
    if not destination.is_relative_to(PROJECT / 'assets/models'):
        raise ValueError('Model output must remain inside assets/models')
    return str(destination)
