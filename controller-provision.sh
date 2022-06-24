#!/bin/bash
# exec 3>&1 4>&2
# trap 'exec 2>&4 1>&3' 0 1 2 3
# exec 1>exec.log 2>&1
mkdir -p host-data
if [ ! -f key.pem ] || [ ! -f .api ]
then
      echo "!!!"
      echo "Cannot provision -- missing API key and/or SSH private key"
      echo "!!!"
    exit
fi
if [ ! -f controller ]
then 
    echo "[controller]" > controller
fi
REMOTE_USER="ubuntu"
VULTR_API_KEY=`cat .api`
INST_NAME="anchor-controller"
INST_DATA="host-data/${INST_NAME}.json"
INST_STATUS="host-data/${INST_NAME}-status.json"
SSH_ID=`curl -s "https://api.vultr.com/v2/ssh-keys" -X GET -H "Authorization: Bearer ${VULTR_API_KEY}"|jq '.ssh_keys | .[]'|jq -r .id`
SSH_PUBKEY=`curl -s "https://api.vultr.com/v2/ssh-keys" -X GET -H "Authorization: Bearer ${VULTR_API_KEY}"|jq '.ssh_keys | .[]'|jq -r .ssh_key`
  echo "==== ==== ===="
  echo "$(date)"
  echo "Provisioning ${INST_NAME}..."
curl -s "https://api.vultr.com/v2/instances" \
-X POST \
  -H "Authorization: Bearer ${VULTR_API_KEY}" \
  -H "Content-Type: application/json" \
    -d '{
    "region" : "ewr",
    "plan" : "vc2-1c-1gb",
    "label" : "'"${INST_NAME}"'",
    "os_id" : 1743,
    "enable_ipv6": "false",
    "backups" : "disabled",
    "hostname": "'"${INST_NAME}"'",
    "sshkey_id": [
        "'"${SSH_ID}"'"
    ],
    "tags": [
      "endpoint",
      "ipv4",
      "ewr"
    ]
  }' > ${INST_DATA}
cat ${INST_DATA}|jq -r
cp ${INST_DATA} ${INST_STATUS}
INST_ID=`cat ${INST_DATA}|jq -r .instance.id`
OS_STATUS=`cat ${INST_STATUS}|jq -r .instance.server_status`

  echo "$(date +%r) Waiting for ${INST_NAME}..."
sleep 300
while [ ${OS_STATUS} != "ok" ]
do
    sleep 60
    curl -s "https://api.vultr.com/v2/instances/${INST_ID}" \
    -X GET \
    -H "Authorization: Bearer ${VULTR_API_KEY}" > ${INST_STATUS}
    OS_STATUS=`cat ${INST_STATUS}|jq -r .instance.server_status`
      echo "$(date +%r) ${INST_NAME} is ${OS_STATUS} -- waiting for installation to complete..."
done
INST_IP=`cat ${INST_STATUS}|jq -r .instance.main_ip`
  echo "${INST_IP} ansible_user=${REMOTE_USER}" >> controller
  echo "$(date +%r) Adding SSH key to user on ${INST_NAME}"
ssh-keyscan -H ${INST_IP} >> ~/.ssh/known_hosts
  echo "Adding pubkey to remote user..."
ssh -i ./key.pem root@${INST_IP} "echo ${SSH_PUBKEY} >> /home/${REMOTE_USER}/.ssh/authorized_keys"
  echo "Enforcing pubkey auth..."
ssh -i ./key.pem root@${INST_IP} "sed -E -i 's|^#?(PasswordAuthentication)\s.*|\1 no|' /etc/ssh/sshd_config && systemctl restart sshd"
ansible-playbook -i controller --private-key=key.pem server.yml