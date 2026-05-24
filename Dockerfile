# ---- client (production) ----
ARG REGISTRY=redhat
FROM ${REGISTRY}/ubi9 AS client

ARG HOCON_JAR_URL
ARG BASH_PKG_VERSION=""

RUN dnf install -y --allowerasing bash jq java-17-openjdk-headless java-17-openjdk-devel curl openssh-clients && dnf clean all
RUN if [ -n "$BASH_PKG_VERSION" ]; then \
      dnf install -y "bash-${BASH_PKG_VERSION}" && dnf clean all; \
    fi

RUN if [ -n "$HOCON_JAR_URL" ]; then \
      curl -fsSL "$HOCON_JAR_URL" -o /usr/local/lib/hocon.jar; \
    fi

WORKDIR /app
COPY . .

# Strip Windows CRLF line endings from shell scripts
RUN find /app -type f \( -name "*.sh" -o -name "sh.bang" -o -name "run-tests" \) \
      -exec sed -i 's/\r$//' {} +

# Build hocon-to-json fat jar (Lightbend config bundled in)
ARG TYPESAFE_CONFIG_JAR_URL=https://repo1.maven.org/maven2/com/typesafe/config/1.4.3/config-1.4.3.jar
RUN curl -fsSL "$TYPESAFE_CONFIG_JAR_URL" -o /tmp/typesafe-config.jar && \
    cd /app/tools/hocon-to-json && \
    javac --release 17 -encoding UTF-8 -cp /tmp/typesafe-config.jar HoconToJson.java && \
    mkdir -p fat && cd fat && jar xf /tmp/typesafe-config.jar && \
    cp ../HoconToJson.class . && \
    jar cfe /usr/local/lib/hocon.jar HoconToJson . && \
    cd .. && rm -rf fat HoconToJson.class /tmp/typesafe-config.jar

ENTRYPOINT ["bin/sh.bang"]

# ---- e2e (test only — not for production use) ----
FROM client AS e2e

# Build replay-stub.jar
RUN cd /app/tools/replay-stub && \
    javac --release 17 -encoding UTF-8 ReplayStub.java && \
    jar cfe replay-stub.jar ReplayStub ReplayStub.class && \
    rm -f ReplayStub.class

# Build bluebird-stub.jar
RUN cd /app/tools/bluebird-stub && \
    javac --release 17 -encoding UTF-8 BluebirdStub.java OrderEventHandler.java TradeEventHandler.java StaticDataHandler.java && \
    jar cfe bluebird-stub.jar BluebirdStub BluebirdStub.class OrderEventHandler.class TradeEventHandler.class StaticDataHandler.class && \
    rm -f BluebirdStub.class OrderEventHandler.class TradeEventHandler.class StaticDataHandler.class

# Build jdi-attacher.jar (requires jdk.jdi module — JDK only, not JRE)
RUN cd /app/tools/jdi-attacher && \
    javac --release 17 -encoding UTF-8 --add-modules jdk.jdi JdiAttacher.java && \
    jar cfe jdi-attacher.jar JdiAttacher JdiAttacher.class && \
    rm -f JdiAttacher.class

# Bake e2e test private key
RUN mkdir -p /root/.ssh && \
    cp tests/e2e/e2e_test_key /root/.ssh/e2e_test_key && \
    chmod 600 /root/.ssh/e2e_test_key

ENTRYPOINT ["bash"]
