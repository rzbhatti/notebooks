#!/usr/bin/bash -l

# create notebooks root
mkdir -p ${NOTEBOOK_ROOT_DIR} 

# Load bash libraries
SCRIPT_DIR=/opt/app-root/bin

if [ -f "${SCRIPT_DIR}/utils/setup-elyra.sh" ]; then
  source ${SCRIPT_DIR}/utils/setup-elyra.sh
fi

# Initialize notebooks arguments variable
NOTEBOOK_PROGRAM_ARGS=""

# Set default ServerApp.port value if NOTEBOOK_PORT variable is defined
if [ -n "${NOTEBOOK_PORT}" ]; then
    NOTEBOOK_PROGRAM_ARGS+="--ServerApp.port=${NOTEBOOK_PORT} "
fi

# Set default ServerApp.base_url value if NOTEBOOK_BASE_URL variable is defined
if [ -n "${NOTEBOOK_BASE_URL}" ]; then
    NOTEBOOK_PROGRAM_ARGS+="--ServerApp.base_url=${NOTEBOOK_BASE_URL} "
fi

# Set default ServerApp.root_dir value if NOTEBOOK_ROOT_DIR variable is defined
if [ -n "${NOTEBOOK_ROOT_DIR}" ]; then
    NOTEBOOK_PROGRAM_ARGS+="--ServerApp.root_dir=${NOTEBOOK_ROOT_DIR} "
else
    NOTEBOOK_PROGRAM_ARGS+="--ServerApp.root_dir=${HOME} "
fi

# Add additional arguments if NOTEBOOK_ARGS variable is defined
if [ -n "${NOTEBOOK_ARGS}" ]; then
    NOTEBOOK_PROGRAM_ARGS+=${NOTEBOOK_ARGS}
fi

# export FLEX_DEVICE="PF"
# export FLEX_COMPUTE="SENTIENT"
export AIU_TOPO_FILE=/etc/ibm/spyre/topo.json
# export FLEX_OVERWRITE_NMB_FRAME="1"
# export FLEX_UNLINK_DEVMEM="false"
export PYTHONUNBUFFERED="1."
export DTLOG_LEVEL="error"
export TORCH_SENDNN_LOG="CRITICAL"
export DT_DEEPRT_VERBOSE="-1"
export INFER_SCRIPT=$(pip show aiu-fms-testing-utils | grep Location | cut -d ' ' -f 2)/aiu_fms_testing_utils/scripts/inference.py
export TORCH_SENDNN_CACHE_DIR=/dev/shm/cache
unset HF_HUB_OFFLINE=0 
unset COMPILATION_MODE
unset FLEX_OVERWRITE_NMB_FRAME

# Set up senlib configuration for AIU
cp /opt/aiu-monitor/etc/senlib_config_aiusmi.json /opt/app-root/etc
cp /opt/app-root/etc/senlib*.json /opt/app-root/src

# Load IBM Spyre AIU setup
source /etc/profile.d/ibm-aiu-setup.sh

# Run Query AIU devices 
touch /tmp/run-aiu-query-devices

 
if [ ! -f ~/.bashrc ]; then
    cp /usr/share/rootfiles/.bashrc ~/
fi

if [ ! -f ~/.bash_logout]; then
    cp /usr/share/rootfiles/.bash_logout ~/
fi

if [ ! -f ~/bash_profile ]; then
    cp /usr/share/rootfiles/.bash_profile ~/
fi

echo """
# Aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias c='clear'
alias h='history'
alias fd='pushd'
alias bd='popd' 

# Run Query AIU devices and save output to a file for display on notebook startup
if [ -f /tmp/run-aiu-query-devices ]; then 
    source /etc/profile.d/ibm-aiu-setup.sh
    /opt/sentient/bin/aiu-query-devices >> /tmp/aiu-query-devices.txt 
    rm /tmp/run-aiu-query-devices
fi

# source /etc/profile.d/ibm-aiu-setup.sh
cat /tmp/aiu-query-devices.txt
# switch to notebooks folder
cd ~/notebooks

""" > ~/.profile

chmod +x ~/.profile

echo "Running command: jupyter lab ${NOTEBOOK_PROGRAM_ARGS} \
    --ServerApp.ip=\"\" \
    --ServerApp.allow_origin=\"*\" \
    --ServerApp.open_browser=False \ $@"


# Start the JupyterLab notebook
exec jupyter lab ${NOTEBOOK_PROGRAM_ARGS} \
    --ServerApp.ip="" \
    --ServerApp.allow_origin="*" \
    --ServerApp.open_browser=False \
    "$@"
