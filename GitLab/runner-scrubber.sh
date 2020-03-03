#!/bin/bash

# A horribly clunky script for attempting to safely clean up after GitLab
# runners that have left all sorts of VirtualBox cruft on the system after a
# Beaker run (or other similar system)
#
# This should only be run when CI jobs are not actively running!

# We're not a gitlab runner
if ! which gitlab-runner >& /dev/null; then
  exit 0
fi

# Bail if rake is running something actively
if pgrep -f '/rake ' >& /dev/null; then
  exit 0
fi

# Shut down for safety
gitlab-runner stop >& /dev/null

# Clean abandoned vagrant processes
for x in `pgrep VBoxH`; do
  if [ ! -e "`realpath \"/proc/${x}/cwd\"`" ]; then
    vmdk_file=`ls -l /proc/${x}/fd | grep '.vmdk' | cut -f2 -d'>'`
    vm_path=`dirname "${vmdk_file}"`
    vm_id=`basename "${vmdk_file}" .vmdk`

    echo "Gracefully Stopping '${vm_id}'"

    runuser gitlab-runner -c "VBoxManage controlvm '${vm_id}' poweroff"
    runuser gitlab-runner -c "VBoxManage unregistervm '${vm_id}' --delete"

    if [ $? -ne 0 ]; then
      echo "Graceful shutdown failed - killing VirtualBox process ${x}"

      kill $x
      sleep 10

      if [ -d "${vm_path}" ]; then
        echo "Removing unused VirtualBox VM directory: ${vm_path}"
        rm -rf "${vm_path}"
      fi
    fi
  fi
done

if ! which lsof >& /dev/null; then
  echo "Error: Could not find lsof, please install and try again"
  gitlab-runner start >& /dev/null
  exit 1
fi

runner_home=`getent passwd gitlab-runner | cut -f6 -d':'`

vbox_vms="${runner_home}/VirtualBox VMs"

# Only do a deep clean if no virtualbox VMs are running
if ! pgrep VBoxH >& /dev/null; then
  if [ -d "${vbox_vms}" ]; then
    for d in "${vbox_vms}"/*; do
      if [ -d "${d}" ]; then
        open_files=`lsof -M +D "${d}"`

        if [ -z "${open_files}" ]; then
          echo "Removing unused VirtualBox VM directory: ${d}"
          rm -rf "${d}"
        fi
      fi
    done
  fi
fi

runuser gitlab-runner -c "for x in `VBoxManage list vms | grep inaccessible | cut -f2 -d'{' | tr -d '}'`; do VBoxManage unregistervm $x; done"

gitlab_config=`gitlab-runner list 2>&1 | grep "ConfigFile" | cut -f2 -d'='`

builds_dirs=`grep builds_dir "${gitlab_config}" | cut -f2 -d'=' | sort -u | tr -d "\"'"`

if [ -z "${builds_dirs}" ]; then
  builds_dirs="${runner_home}/builds"
fi

for x in $builds_dirs; do
  for d in "${x}"/*; do
    if [ -d "${d}" ]; then
      open_files=`lsof -M +D "${d}"`

      if [ -z "${open_files}" ]; then
        echo "Removing unused build dir: ${d}"
        rm -rf "${d}"
      fi
    fi
  done
done

gitlab-runner start >& /dev/null
