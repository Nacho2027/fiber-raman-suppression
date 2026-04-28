FROM julia:1.12.6-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    JULIA_NUM_THREADS=auto \
    JULIA_PKG_PRECOMPILE_AUTO=0 \
    MPLBACKEND=Agg \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:$PATH

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        fontconfig \
        g++ \
        gcc \
        git \
        make \
        python3 \
        python3-dev \
        python3-pip \
        python3-venv \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace/fiber-raman-suppression

COPY Project.toml Manifest.toml pyproject.toml README.md ./
COPY python ./python

RUN python3 -m venv /opt/venv \
    && pip install --upgrade pip \
    && pip install -e . matplotlib \
    && PYTHON=/opt/venv/bin/python julia --project=. -e 'using Pkg; Pkg.instantiate(; allow_autoprecomp=false); Pkg.build("PyCall")'

COPY . .

RUN PYTHON=/opt/venv/bin/python julia --project=. -e 'using Pkg; Pkg.precompile()'

ENV VENV=/opt/venv

CMD ["make", "doctor"]
