FROM python:3.12-alpine

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app

WORKDIR /app

RUN apk add --no-cache \
        libpq \
    && apk add --no-cache --virtual .build-deps \
        gcc \
        musl-dev \
        postgresql-dev \
        libffi-dev \
        openssl-dev

COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt \
    && apk del .build-deps

COPY . .

RUN addgroup -S django \
    && adduser -S -G django django \
    && mkdir -p /app/staticfiles \
    && chown -R django:django /app

USER django

RUN DATABASE_URL=sqlite:////tmp/build.sqlite3 python manage.py collectstatic --noinput

EXPOSE 8000

CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "--access-logfile", "-", "config.wsgi:application"]
