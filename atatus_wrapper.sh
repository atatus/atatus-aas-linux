#!/usr/bin/env bash

main() {
    export ATATUS_AZURE_APP_SERVICES=1
    export ATATUS_HOSTNAME="none"

    if [ -z "${ATATUS_CHDIR}" ]; then
        CURRENT_DIR=$(pwd)
    else
        CURRENT_DIR="$(pwd)/${ATATUS_CHDIR}"
    fi

    echo "Set application directory as ${CURRENT_DIR}"

    echo "Setting Atatus environment variables"
    setEnvVars

    echo "Creating and switching to the Atatus directory at ${ATATUS_DIR}"
    mkdir -p "${ATATUS_DIR}" && cd "${ATATUS_DIR}" || return

    echo "Adding Runtime specific dependencies"
    getRuntimeDependencies

    case "$WEBSITE_STACK" in
        "NODE")
            setUpNodeEnv;;
        "DOTNETCORE")
            setUpDotnetEnv;;
        "JAVA")
            setUpJavaEnv;;
        "PHP")
            setupPHPEnv;;
        "PYTHON")
            setUpPyEnv;;
        "TOMCAT")
            setUpJavaEnv;;
        "*")
            echo "Unsupported runtime. Exiting Atatus startup"
            return;;
    esac

    echo "Completed Atatus setup"
}

setEnvVars() {
    if [ -z "${ATATUS_DIR}" ]; then
        ATATUS_DIR="/home/atatus"
    fi
}

getRuntimeDependencies() {
    # If we are in Java, Tomcat or PHP stacks, we need to find the linux type to install unzip and curl
    if [ "${WEBSITE_STACK}" == "JAVA" ] || [ "${WEBSITE_STACK}" == "TOMCAT" ] || [ "${WEBSITE_STACK}" == "PHP" ]; then
        LINUX_VERSION_NAME=$(. "/etc/os-release"; echo "$ID")
        if [ "${LINUX_VERSION_NAME}" == "ubuntu" ] || [ "${LINUX_VERSION_NAME}" == "debian" ]; then
            apt-get update
            apt-get install -y unzip
            apt-get install -y curl
        else
            apk add curl
            apk add libc6-compat
        fi
    fi
}

setUpNodeEnv() {
    NODE_RUNTIME_VERSION=$(node --version)
    echo "Found runtime version ${NODE_RUNTIME_VERSION}"
    echo "Setting up Atatus agent for Node"
    echo "Installing Node agent"

    if [[ "$NODE_RUNTIME_VERSION" =~ ^v16.* ]]; then
        yarn add "atatus-nodejs" || return
    else
        yarn add atatus-nodejs || return
    fi

    ORIG_NODE_OPTIONS=$NODE_OPTIONS
    export NODE_OPTIONS="--require=${ATATUS_DIR}/node_modules/atatus-nodejs/start ${ORIG_NODE_OPTIONS}"

    # confirm updates to NODE_OPTIONS
    node --help >/dev/null || (export NODE_OPTIONS="${ORIG_NODE_OPTIONS}" && return)
}

setUpDotnetEnv() {
    echo "Setting up Atatus profiler for .NET"
    if [ -z "${ATATUS_DOTNET_PROFILER_VERSION}" ]; then
        ATATUS_DOTNET_PROFILER_VERSION=2.0.1
    fi

    ATATUS_DOTNET_PROFILER_DIR="${ATATUS_DIR}/atatus-dotnet-${ATATUS_DOTNET_PROFILER_VERSION}"

    if [ ! -d "$ATATUS_DOTNET_PROFILER_DIR" ]; then
        mkdir -p "${ATATUS_DOTNET_PROFILER_DIR}" && cd "${ATATUS_DOTNET_PROFILER_DIR}" || return

        ATATUS_DOTNET_PROFILER_FILE=atatus-dotnet-agent-profiler-${ATATUS_DOTNET_PROFILER_VERSION}-linux-x64.zip
        ATATUS_DOTNET_PROFILER_URL=https://atatus-artifacts.s3.amazonaws.com/atatus-dotnet/downloads/${ATATUS_DOTNET_PROFILER_FILE}

        if curl -L --fail "${ATATUS_DOTNET_PROFILER_URL}" -o "${ATATUS_DOTNET_PROFILER_FILE}"; then
            unzip "${ATATUS_DOTNET_PROFILER_FILE}" || return
        else
            echo "Downloading the profiler was unsuccessful"
            return
        fi

    fi

    export CORECLR_ENABLE_PROFILING=1
    export CORECLR_PROFILER="{A6C28362-6F75-472A-B36C-50C1644DA40A}"
    export CORECLR_PROFILER_PATH="${ATATUS_DOTNET_PROFILER_DIR}/libatatus_profiler.so"
    export ATATUS_PROFILER_HOME="${ATATUS_DOTNET_PROFILER_DIR}"
    export ATATUS_PROFILER_INTEGRATIONS="${ATATUS_DOTNET_PROFILER_DIR}/integrations.yml"
}

setUpJavaEnv() {
    echo "Setting up Atatus agent for Java"
    if [ -z "${ATATUS_JAVA_AGENT_VERSION}" ]; then
        ATATUS_JAVA_AGENT_VERSION=latest
    fi

    echo "Using version ${ATATUS_JAVA_AGENT_VERSION} of the JAVA agent"
    ATATUS_JAVA_AGENT_FILE="atatus-java-agent.jar"
    ATATUS_JAVA_AGENT_URL="https://atatus-artifacts.s3.amazonaws.com/atatus-java/downloads/${ATATUS_JAVA_AGENT_VERSION}/${ATATUS_JAVA_AGENT_FILE}"

    echo "Installing JAVA agent from ${ATATUS_JAVA_AGENT_URL}"
    if ! curl -L --fail "${ATATUS_JAVA_AGENT_URL}" -o "${ATATUS_JAVA_AGENT_FILE}"; then
        echo "Downloading the agent was unsuccessful"
        return
    fi

    echo "Adding the Atatus JAVA agent to the startup command"
    ATATUS_JAVAAGENT="-javaagent:${ATATUS_DIR}/${ATATUS_JAVA_AGENT_FILE}"

    if [ "${WEBSITE_STACK}" == "TOMCAT" ]; then
        export JAVA_OPTS="${JAVA_OPTS} ${ATATUS_JAVAAGENT}"
    else
        ATATUS_START_APP=$(echo "${ATATUS_START_APP//-jar/$ATATUS_JAVAAGENT -jar}")
    fi
}

setupPHPEnv() {
    echo "Setting up Atatus agent for PHP"
    if [ -z "${ATATUS_PHP_AGENT_VERSION}" ]; then
        ATATUS_PHP_AGENT_VERSION=1.15.2
    fi

    ATATUS_PHP_AGENT_URL=https://s3.amazonaws.com/atatus-artifacts/atatus-php/downloads/${ATATUS_PHP_AGENT_VERSION}/atatus-setup.php

    echo "Installing PHP agent from ${ATATUS_PHP_AGENT_URL}"
    if curl -LO --fail "${ATATUS_PHP_AGENT_URL}"; then
        eval "php atatus-setup.php --php-bin=all"
    else
        echo "Downloading the agent was unsuccessful"
        return
    fi
}

setUpPyEnv() {
    echo "Setting up atatus agent for Python"
    if [ -z "${ATATUS_PYTHON_AGENT_VERSION}" ]; then
        ATATUS_PYTHON_AGENT_VERSION=1.5.4
    fi

    pip install atatus
    # append atatus-run command to original start command
    ATATUS_START_APP="atatus-run ${ATATUS_START_APP}"
}

main
echo "Executing start command: \"${ATATUS_START_APP}\""
cd "${CURRENT_DIR}"
eval "${ATATUS_START_APP}"