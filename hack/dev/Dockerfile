# Runtime-only image for the local development loop.
#
# The binary is cross-compiled on the host by hack/dev/build.sh using the Go
# toolchain from the Flox environment, so this build stays a sub-second file
# copy instead of a multi-hundred-megabyte golang base image pull. The
# repository root Dockerfile remains the canonical, self-contained build.
FROM gcr.io/distroless/static:nonroot

COPY astro /astro
COPY conf.yml /conf.yml

USER 65532:65532
ENTRYPOINT ["/astro"]
