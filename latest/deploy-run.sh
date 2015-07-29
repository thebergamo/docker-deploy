set -e

echo > playbooks/roles/configure/files/authorized_keys
cat ${LOCAL_ROOT_DOT_SSH_PATH}/*.pub >> playbooks/roles/configure/files/authorized_keys

[ -z ${REMOTE_HOST} ] && echo "REMOTE_HOST is missing." && exit 1

export ANSIBLE_HOST_KEY_CHECKING=False

[ -z ${REMOTE_USER} ] && \
  REMOTE_USER='git'
[ -z ${REMOTE_PASS} ] && \
  REMOTE_PASS=$( date +%s | sha256sum | base64 | head -c 32 | sha256sum | awk '{print $1}' )
[ -z ${REMOTE_ROOT_USER} ] && \
  REMOTE_ROOT_USER='root'
[ -z ${REMOTE_PORT} ] && \
  REMOTE_PORT='22'
[ -z ${AZK_DOMAIN} ] && \
  AZK_DOMAIN='dev.azk.io'
[ -z "${AZK_RESTART_COMMAND}" ] && \
  AZK_RESTART_COMMAND='azk restart -R'
[ -z ${GIT_CHECKOUT_COMMIT_BRANCH_TAG} ] && \
  GIT_CHECKOUT_COMMIT_BRANCH_TAG='master'

[ -z ${GIT_REMOTE} ] && \
  GIT_REMOTE='azk_deploy'

if ( cd ${LOCAL_PROJECT_PATH}; git remote | grep -q "^${GIT_REMOTE}$" ); then
  REMOTE_PROJECT_PATH=$( cd ${LOCAL_PROJECT_PATH}; git remote -v | grep -P "^${GIT_REMOTE}\t" | head -1 | awk '{ print $2 }' | sed 's/.*\:\/\/.*@[^:]*\(:[0-9]\+\)\?//' | sed 's/\.git//' )
else
  [ -z ${REMOTE_PROJECT_PATH_ID} ] && \
    REMOTE_PROJECT_PATH_ID=$( date +%s | sha256sum | head -c 7 )
  [ -z $REMOTE_PROJECT_PATH ] && \
    REMOTE_PROJECT_PATH="/home/${REMOTE_USER}/${REMOTE_PROJECT_PATH_ID}"
fi
REMOTE_GIT_PATH="${REMOTE_PROJECT_PATH}.git"

(
  echo -n "default ansible_ssh_host=${REMOTE_HOST} "
  echo -n "ansible_ssh_port=${REMOTE_PORT} "
  echo -n "ansible_ssh_user=${REMOTE_ROOT_USER} "
  ( [ ! -z ${REMOTE_ROOT_PASS} ] && echo -n "ansible_ssh_pass=${REMOTE_ROOT_PASS}" ) || true
) > /etc/ansible/hosts

if [ -z ${RUN_SETUP} ] || [ "${RUN_SETUP}" = "true" ]; then
  # Provisioning
  ansible-playbook playbooks/setup.yml
  ansible-playbook playbooks/reset.yml || true
fi

if [ -z ${RUN_CONFIGURE} ] || [ "${RUN_CONFIGURE}" = "true" ]; then
  # Configuring
  ansible-playbook playbooks/configure.yml --extra-vars "user=${REMOTE_USER} src_dir=${REMOTE_PROJECT_PATH} git_dir=${REMOTE_GIT_PATH} azk_domain=${AZK_DOMAIN} azk_restart_command='${AZK_RESTART_COMMAND}' git_checkout_commit_branch_tag=${GIT_CHECKOUT_COMMIT_BRANCH_TAG}"
fi

if [ -z ${RUN_DEPLOY} ] || [ "${RUN_DEPLOY}" = "true" ]; then
  # Deploying
  $( cd ${LOCAL_PROJECT_PATH}
  quiet git remote rm ${GIT_REMOTE} || true
  quiet git remote add ${GIT_REMOTE} ssh://${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PORT}${REMOTE_GIT_PATH} || true
  git push ${GIT_REMOTE} ${GIT_CHECKOUT_COMMIT_BRANCH_TAG} )
fi

echo
echo "App successfully deployed at http://${REMOTE_HOST}"

set +e