FROM registry.redhat.io/ansible-automation-platform/ee-minimal-rhel9:latest

COPY requirements.yml /tmp/requirements.yml
COPY requirements.txt /tmp/requirements.txt

RUN pip3 install --upgrade pip && \
    pip3 install -r /tmp/requirements.txt

RUN ansible-galaxy collection install -r /tmp/requirements.yml -p /usr/share/ansible/collections
