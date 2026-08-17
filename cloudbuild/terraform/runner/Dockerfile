ARG TERRAFORM_VERSION=1.13.3
FROM hashicorp/terraform:${TERRAFORM_VERSION}

USER root
RUN apk add --no-cache bash curl ca-certificates git openssh-client

ENTRYPOINT ["terraform"]
