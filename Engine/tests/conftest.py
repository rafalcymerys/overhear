import pytest

from .harness import Engine


def pytest_addoption(parser):
    parser.addoption(
        "--run-slow",
        action="store_true",
        default=False,
        help="also run tests that load the real openwakeword / whisper models",
    )


def pytest_configure(config):
    config.addinivalue_line("markers", "slow: loads real ML models (minutes, not seconds)")


def pytest_collection_modifyitems(config, items):
    if config.getoption("--run-slow"):
        return
    skip = pytest.mark.skip(reason="needs --run-slow")
    for item in items:
        if "slow" in item.keywords:
            item.add_marker(skip)


@pytest.fixture
def engine_factory():
    """Build engines with arbitrary arguments; all are torn down afterwards."""
    built = []

    def build(languages="en", cancel_word="hey_jarvis", stub_models=True, start=True):
        engine = Engine(languages=languages, cancel_word=cancel_word, stub_models=stub_models)
        built.append(engine)
        if start:
            engine.start()
        return engine

    yield build

    for engine in built:
        engine.close()


@pytest.fixture
def engine(engine_factory):
    """A started, idle, single-language engine — the common case."""
    return engine_factory().wait_until_idle()
