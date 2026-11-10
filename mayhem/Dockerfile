# syntax=docker/dockerfile:1.7
#
# Commit image for reshade: the ReShade FX effect compiler (preprocessor, parser, HLSL/GLSL/SPIR-V
# code generators) built from source/effect_*.cpp with sanitizers, plus the fuzz harnesses.
#
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile --build-arg COMMIT=$(git rev-parse HEAD) -t mytag .
FROM ghcr.io/savantenvs/base:20261023

ARG COMMIT
ARG REPO_URL
ARG SOURCE_DATE_EPOCH
ARG SANITIZER_FLAGS
ARG COVERAGE_FLAGS=
ARG MAYHEM_JOBS=

# deps/spirv is a git submodule (KhronosGroup/SPIRV-Headers) that the commit checkout does not contain, and
# the build must run offline afterwards: cache the exact commit upstream pins in the in-image deps tree
# (SPEC §6.2 item 19). Headers only, so there is nothing to compile; build.sh just adds -I .../include.
USER root
ARG SPIRV_HEADERS_REV=7845730cab6ebbdeb621e7349b7dc1a59c3377be
ARG SPIRV_HEADERS_SHA256=18d0841f8b510c6ee7e361e725bddef5913dbacb507cbd6951fbc29f15474288
RUN d=/opt/toolchains/deps/spirv-headers-${SPIRV_HEADERS_REV} && mkdir -p "$d/src" "$d/include" \
 && curl -fsSL -o /tmp/spirv-headers.tgz \
      https://github.com/KhronosGroup/SPIRV-Headers/archive/${SPIRV_HEADERS_REV}.tar.gz \
 && echo "${SPIRV_HEADERS_SHA256}  /tmp/spirv-headers.tgz" | sha256sum -c - \
 && tar -xzf /tmp/spirv-headers.tgz --strip-components=1 -C "$d/src" \
 && cp "$d/src/include/spirv/unified1/spirv.hpp" "$d/src/include/spirv/unified1/GLSL.std.450.h" "$d/include/" \
 && rm -f /tmp/spirv-headers.tgz && chmod -R a+rX "$d"

USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN if [ -x /opt/mayhem/ccache/prefill ]; then /opt/mayhem/ccache/prefill bash mayhem/build.sh; \
    else bash mayhem/build.sh; fi

RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh — repo ships no functional tests"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
