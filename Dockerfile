FROM julia:1.12.6-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    JULIA_NUM_THREADS=auto \
    JULIA_PKG_PRECOMPILE_AUTO=0 \
    MPLBACKEND=Agg \
    PYTHON=/usr/bin/python3

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        fontconfig \
        g++ \
        gcc \
        git \
        make \
        python3 \
        python3-matplotlib \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace/fiber-raman-suppression

COPY Project.toml Manifest.toml ./

RUN julia --project=. -e 'using Pkg; Pkg.instantiate(; allow_autoprecomp=false); Pkg.build("PyCall")'

COPY . .

RUN julia --project=. -e 'using Pkg; Pkg.precompile()'

CMD ["make", "doctor"]
