# Client: runs sh.bang, converts HOCON, dispatches to servers
FROM redhat/ubi9

ARG HOCON_JAR_URL

RUN dnf install -y bash jq java-17-openjdk-headless curl openssh-clients && dnf clean all

RUN if [ -n "$HOCON_JAR_URL" ]; then \
      curl -fsSL "$HOCON_JAR_URL" -o /usr/local/lib/hocon.jar; \
    fi

WORKDIR /app
COPY . .

ENTRYPOINT ["bin/sh.bang"]
