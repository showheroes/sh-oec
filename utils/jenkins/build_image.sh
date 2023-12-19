#!/bin/bash

# A helper script to build the Docker image from Jenkins.
#

# The script uses Docker buildkit and can use a Docker Cache Registry to load/save cache.
#
# The following env vars must be set by the Jenkinsfile:
#
# * IMAGE_NAME: just the image name. For example: "sh-playbooks"
# * GAR_REPO: the target GAR repo in the form <project-id>/<repo-name>
# * GAR_LOCATIONS: comma separated list of target GAR registry locations
#
# The following env vars must be set on the Jenkins Agent Container via the Jenkins UI
#
# * DOCKER_CACHE_REGISTRY: url of the Docker Cache Registry. Currently: "dcr.docker-cache-registry:5000". Override to "" will disable the cache
# * BUILDKIT_TOML_PATH: the path to a buildkit.toml config file. Used only if DOCKER_CACHE_REGISTRY env var is not empty
#

set -euo pipefail

# ensure needed variables are set
# shellcheck disable=SC2269
GIT_COMMIT=${GIT_COMMIT}
# shellcheck disable=SC2269
IMAGE_NAME=${IMAGE_NAME}
# shellcheck disable=SC2269
GAR_REPO=${GAR_REPO}
# shellcheck disable=SC2269
GAR_LOCATIONS=${GAR_LOCATIONS}

echo "GIT_COMMIT: ${GIT_COMMIT}"
echo "IMAGE_NAME: ${IMAGE_NAME}"

# check optional vars
DOCKER_CACHE_REGISTRY=${DOCKER_CACHE_REGISTRY:-""}
BUILDKIT_TOML_PATH=${BUILDKIT_TOML_PATH:-""}
DOCKERFILE=${DOCKERFILE:-Dockerfile}

# set some var depending on the env
# If the build is for a PR it's the PR's target branch
CHANGE_TARGET=${CHANGE_TARGET:-}
# If the build is for a PR it's the PR source branch. Otherwise the built branch
CURRENT_BRANCH=${CHANGE_BRANCH:-$BRANCH_NAME}
# Previous commit id might end up very useful on the master branch.
# Normally master commits are merge commits for which the previous commit id
# correspond to the already built PR branch.
GIT_PREV_COMMIT="$(git log --format="%H" -n 2 | tail -n 1)"

# set target images
TARGET_REGISTRIES=()
TARGET_REGISTRIES_PATH=()
TARGET_IMAGES=()
IFS=', ' eval 'LOCATIONS=($GAR_LOCATIONS)'
for L in "${LOCATIONS[@]}"; do
    TARGET_REGISTRIES+=("${L}-docker.pkg.dev")
    TARGET_REGISTRIES_PATH+=("${L}-docker.pkg.dev/${GAR_REPO}")
done
TARGET_TAGS=("${GIT_COMMIT}" "${CURRENT_BRANCH}")
if [ "$CURRENT_BRANCH" = "master" ]; then
    TARGET_TAGS+=("latest")
fi

for R in "${TARGET_REGISTRIES_PATH[@]}"; do
    for T in "${TARGET_TAGS[@]}"; do
        TARGET_IMAGES+=("${R}/${IMAGE_NAME}:${T}")
    done
done

echo "CHANGE_TARGET: ${CHANGE_TARGET}"
echo "CURRENT_BRANCH: ${CURRENT_BRANCH}"

BUILD_COMMAND=("docker" "buildx" "build" "-f" "$DOCKERFILE" "--push")
echo "The following images will be pushed:"
for I in "${TARGET_IMAGES[@]}"; do
    echo " * ${I}"
    BUILD_COMMAND+=("-t" "${I}")
done

echo "Authenticate docker"
printf -v R_LIST '%s,' "${TARGET_REGISTRIES[@]}"
gcloud auth configure-docker "${R_LIST%,}"

CACHE_FROM=()
CACHE_TO=()

if [ -n "${DOCKER_CACHE_REGISTRY}" ]; then
    CACHE_FROM=("${DOCKER_CACHE_REGISTRY}/${IMAGE_NAME}:latest" "${DOCKER_CACHE_REGISTRY}/${IMAGE_NAME}:${CURRENT_BRANCH}" "${DOCKER_CACHE_REGISTRY}/${IMAGE_NAME}:${GIT_COMMIT}" "${DOCKER_CACHE_REGISTRY}/${IMAGE_NAME}:${GIT_PREV_COMMIT}")
    CACHE_TO=("${DOCKER_CACHE_REGISTRY}/${IMAGE_NAME}:${GIT_COMMIT}" "${DOCKER_CACHE_REGISTRY}/${IMAGE_NAME}:${CURRENT_BRANCH}")
    if [ -n "$CHANGE_TARGET" ]; then
        CACHE_FROM+=("${DOCKER_CACHE_REGISTRY}/${IMAGE_NAME}:${CHANGE_TARGET}")
    fi
    if [ "$CURRENT_BRANCH" = "master" ]; then
        CACHE_TO+=("${DOCKER_CACHE_REGISTRY}/${IMAGE_NAME}:latest")
    fi
fi
echo "Cache From:"
for i in "${CACHE_FROM[@]}"; do
    echo " * $i"
    BUILD_COMMAND+=("--cache-from=type=registry,ref=$i")
done

echo "Cache To:"
for i in "${CACHE_TO[@]}"; do
    echo " * $i"
    BUILD_COMMAND+=("--cache-to=type=registry,ref=$i")
done

docker buildx create --use --name mybuilder --driver-opt network=host --config "$BUILDKIT_TOML_PATH"

echo "buildx command: "
echo "${BUILD_COMMAND[@]}"

"${BUILD_COMMAND[@]}" .
