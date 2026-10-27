# Load the AI Hub EAP image first (see README):
#   docker image load -i iris-community-2026.3.0AI.154.0-docker.tar.gz
# The default is the name the archive loads with; docker-compose.yml overrides it with IRIS_IMAGE from .env.
ARG IMAGE=docker.iscinternal.com/docker-intersystems/intersystems/iris-community:2026.3.0AI.154.0
FROM $IMAGE

WORKDIR /home/irisowner/dev

COPY --chown=irisowner:irisowner merge.cpf iris.script ./
COPY --chown=irisowner:irisowner src ./src
COPY --chown=irisowner:irisowner runbooks ./runbooks
COPY --chown=irisowner:irisowner web ./web
COPY --chown=irisowner:irisowner recordings ./recordings
COPY --chown=irisowner:irisowner mcp ./mcp

RUN iris start IRIS && \
    iris merge IRIS /home/irisowner/dev/merge.cpf && \
    iris session IRIS < /home/irisowner/dev/iris.script && \
    iris stop IRIS quietly
