VERSION=$1
ansible-builder build -v 3 -t jellebens/ansible-excecution-environment:$VERSION --container-runtime podman

podman push jellebens/ansible-excecution-environment:$VERSION
