# Python Dependencies

## Install

```bash
pip install opentelemetry-sdk opentelemetry-exporter-otlp opentelemetry-instrumentation
```

Or with `uv`:

```bash
uv add opentelemetry-sdk opentelemetry-exporter-otlp opentelemetry-instrumentation
```

## Wire Entry Point

Add to the **top** of your main file (must be first import):

```python
import instrumentation
```

## Framework Auto-Instrumentation

Install framework-specific packages for automatic span creation:

### FastAPI

```bash
pip install opentelemetry-instrumentation-fastapi
```

```python
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
FastAPIInstrumentor.instrument()
```

### Django

```bash
pip install opentelemetry-instrumentation-django
```

Add to `INSTALLED_APPS` or call before `django.setup()`:

```python
from opentelemetry.instrumentation.django import DjangoInstrumentor
DjangoInstrumentor().instrument()
```

### Flask

```bash
pip install opentelemetry-instrumentation-flask
```

```python
from opentelemetry.instrumentation.flask import FlaskInstrumentor
FlaskInstrumentor().instrument_app(app)
```
