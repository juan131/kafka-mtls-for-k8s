# Kafka with Mutual TLS for K8s

[Bitnami charts](https://github.com/bitnami/charts) is the easiest way to get started with open-source applications on Kubernetes. It provides you a secure, up-to-date and easy-to-use catalog with 140+ applications.

Most users install the Bitnami charts with the default values, which is a great way to start with your favorite app on K8s using a simple structure. That said, **these charts can offer you much more**. They provide support for different topologies, configurations, integrations, customizations, etc.

This repository is a guide attempts to **unleash the potential of the Bitnami catalog**. To do so, it walks through the steps required to deploy on K8s a Kafka cluster with Mutual TLS with TLS secrets managed by Cert Manager. This setups provide you:

- High Availability.
- 2-way authentication.
- Encryption both in client-broker and inter-broker communications.
- TLS certificates management and issuance via Cert Manager.

## TL;DR

```console
$ git clone https://github.com/juan131/kafka-mtls-for-k8s.git && cd kafka-mtls-for-k8s
$ ./setup.sh
```

## Before you begin

### Prerequisites

- [Kubernetes](https://kubernetes.io/) 1.12+
- [Helm](https://helm.sh/) 3.1.0
- [Dynamic Volume Provisioning](https://kubernetes.io/docs/concepts/storage/dynamic-provisioning/) support in the underlying infrastructure

### Setup a Kubernetes Cluster & Install Helm

Follow the instruction under the "Before you being" section of the README.md file below:

- [Before you begin](https://github.com/bitnami/charts#before-you-begin).

## How to use this tutorial

This tutorial provides a script ([setup.sh](setup.sh)) that you can use to deploy all the required solutions in your Kubernetes cluster in a orchestrated way.

As an alternative, you can manually install each of the required charts. The tutorial makes use of the following Helm charts:

- [Bitnami Kafka](https://github.com/bitnami/charts/tree/master/bitnami/kafka).
- [Bitnami Zookeeper](https://github.com/bitnami/charts/tree/master/bitnami/zookeeper).
- [Bitnami Cert Manager](https://github.com/bitnami/charts/tree/master/bitnami/cert-manager).

You can find the corresponding **values.yaml** to deploy each of these charts under the *values/* directory.

## Testing the setup

Once you deploy the required solutions, you can use the [test.sh](test.sh) script to test everything is working as expected.
