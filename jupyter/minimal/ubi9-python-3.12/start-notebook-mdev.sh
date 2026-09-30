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

# Spyre device selection. These are baked as ENV in Dockerfile.mdev
# (FLEX_COMPUTE=hardware, FLEX_DEVICE=PF); assigned here with ${VAR:=default} so
# they are still correct if this script is run in a container built without them,
# while remaining overridable at pod level for simulator runs
# (FLEX_COMPUTE=SENTIENT or MOCK). Without the pair, torch-spyre's device backend
# does not autoload and tensor.to("spyre") raises.
: "${FLEX_DEVICE:=PF}"
: "${FLEX_COMPUTE:=hardware}"
export FLEX_DEVICE FLEX_COMPUTE

# NOTE: ibm-aiu-setup.sh (sourced below) generates topo.json under
# /tmp/etc/ibm/spyre and re-exports AIU_TOPO_FILE, overriding this value.
export AIU_TOPO_FILE=/etc/ibm/spyre/topo.json
# export FLEX_OVERWRITE_NMB_FRAME="1"
# export FLEX_UNLINK_DEVMEM="false"
export PYTHONUNBUFFERED="1"
export DTLOG_LEVEL="error"
export TORCH_SENDNN_LOG="CRITICAL"
export DT_DEEPRT_VERBOSE="-1"
export INFER_SCRIPT=$(pip show aiu-fms-testing-utils | grep Location | cut -d ' ' -f 2)/aiu_fms_testing_utils/scripts/inference.py
export TORCH_SENDNN_CACHE_DIR=/dev/shm/cache
export HF_HUB_OFFLINE=0
unset COMPILATION_MODE
unset FLEX_OVERWRITE_NMB_FRAME

# --- vLLM on Spyre -----------------------------------------------------------
# Also baked as ENV in the Dockerfile; defaulted here so a container built from
# an older image still works, and so pod-level overrides win.
#
# VLLM_PLUGINS: without it vLLM silently selects the CPU platform and never
# touches the card.
: "${VLLM_PLUGINS:=spyre_inference,spyre_inference_ops}"
# SPYRE_BATCHED_DECODE=0 is REQUIRED for granite-4.2-8b on this stack: with the
# default (1) every batched-decode attention variant fails to compile in
# torch_spyre/_inductor/wsr/for_each_tile_lowering.py ("tile_dim_marker op ... has
# 2 consuming reads within its spliced body") and the engine dies during warmup.
: "${SPYRE_BATCHED_DECODE:=0}"
# SPYRE_ATTN_FOR_EACH_TILE=0 is REQUIRED for the same reason at the other end of
# the pipeline: with the default (1) the paged-attention variants hit the same
# assertion on the first real forward pass (warmup only warns "failed to record").
# 0 runs the identical kernel body under a Python for-loop via walk_tiles() instead
# of torch-spyre's for_each_tile -- a loop-driver choice, not a numerics change.
# Bucket sizes and SPYRE_ATTN_KV_LAYOUT are not workarounds; both were measured.
: "${SPYRE_ATTN_FOR_EACH_TILE:=0}"
# Persistent compiled-kernel cache on the PVC, so warm compiles survive restarts.
# The cache key includes the native stack versions from LIB_VERSION_FILE, so it
# self-invalidates when the Spyre stack is upgraded.
: "${SPYRE_KERNEL_CACHE:=1}"
: "${TORCHINDUCTOR_CACHE_DIR:=/opt/app-root/src/.cache/torchinductor-spyre}"
: "${HF_HOME:=/opt/app-root/src/.cache/huggingface}"
export VLLM_PLUGINS SPYRE_BATCHED_DECODE SPYRE_ATTN_FOR_EACH_TILE \
       SPYRE_KERNEL_CACHE TORCHINDUCTOR_CACHE_DIR HF_HOME
mkdir -p "${TORCHINDUCTOR_CACHE_DIR}" "${HF_HOME}" 2>/dev/null || true

# ${HOME} is a mounted PVC. A `pip install --user` there lands in
# ${HOME}/.local/lib/python3.12/site-packages and survives every image rebuild.
# It no longer shadows the baked-in stack (those paths were removed from
# PYTHONPATH in Dockerfile.mdev), but a stale copy of torch or transformers there
# can still be picked up ahead of /usr/local via site.USER_SITE, so make it
# visible rather than silently deleting a user's work.
for _user_site in "${HOME}/.local/lib/python3.12/site-packages" \
                  "${HOME}/.local/lib64/python3.12/site-packages"; do
    if [ -d "${_user_site}" ] && [ -n "$(ls -A "${_user_site}" 2>/dev/null)" ]; then
        echo "WARNING: user site-packages present on the PVC: ${_user_site}"
        echo "         The Spyre stack is preinstalled system-wide in /usr/local."
        echo "         Packages here can shadow it. Verify with:"
        echo "           python3 -c 'import torch; print(torch.__file__, torch.__version__)'"
        echo "         and remove stale copies with: pip uninstall --user <pkg>"
    fi
done
unset _user_site

# Set up senlib configuration for AIU
# /opt/aiu-monitor does not exist in this base image; no senlib_config_aiusmi.json
# is shipped. Left disabled (as on the spyre branch) until the base image provides it.
# cp /opt/aiu-monitor/etc/senlib_config_aiusmi.json /opt/app-root/etc
cp /opt/app-root/etc/senlib*.json /opt/app-root/src/ 2>/dev/null || true

# Load IBM Spyre AIU setup
source /etc/profile.d/ibm-aiu-setup.sh

# Run Query AIU devices 
touch /tmp/run-aiu-query-devices

 
if [ ! -f ~/.bashrc ]; then
    cp /usr/share/rootfiles/.bashrc ~/ 2>/dev/null || true
fi

if [ ! -f ~/.bash_logout ]; then
    cp /usr/share/rootfiles/.bash_logout ~/ 2>/dev/null || true
fi

if [ ! -f ~/.bash_profile ]; then
    cp /usr/share/rootfiles/.bash_profile ~/ 2>/dev/null || true
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

# --- Spyre / vLLM environment ------------------------------------------------
# A JupyterLab terminal is a fresh login shell and does NOT inherit this
# entrypoint's exports, so re-export them here. This is what makes offline vLLM
# inference and 'vllm serve' work in a terminal with no manual setup.
export FLEX_DEVICE=\"${FLEX_DEVICE}\"
export FLEX_COMPUTE=\"${FLEX_COMPUTE}\"
export VLLM_PLUGINS=\"${VLLM_PLUGINS}\"
export SPYRE_BATCHED_DECODE=\"${SPYRE_BATCHED_DECODE}\"
export SPYRE_ATTN_FOR_EACH_TILE=\"${SPYRE_ATTN_FOR_EACH_TILE}\"
export SPYRE_KERNEL_CACHE=\"${SPYRE_KERNEL_CACHE}\"
export TORCHINDUCTOR_CACHE_DIR=\"${TORCHINDUCTOR_CACHE_DIR}\"
export HF_HOME=\"${HF_HOME}\"
export DTLOG_LEVEL=\"${DTLOG_LEVEL}\"
export DT_DEEPRT_VERBOSE=\"${DT_DEEPRT_VERBOSE}\"
export TORCH_SENDNN_LOG=\"${TORCH_SENDNN_LOG}\"
export PYTHONUNBUFFERED=\"${PYTHONUNBUFFERED}\"

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
