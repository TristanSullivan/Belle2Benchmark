#!/bin/bash

#set -e # immediate exit on error

# Naming convention for environment variable in this script (BMK-118):
# - All uppercase environment variables may be used across different functions
#   > All variables starting with CI_ are set by the gitlab runner CI
#   > All variables starting with CIENV_ are set in .gitlab-ci.sh or .gitlab-ci.yml
#   > All variables starting with HEPWL_ are set in the spec file of each workload
#   > All variables starting with MAIN_ are set in this main.sh from user inputs or other variables
# - All lowercase environment variables are meant to remain local to their script/function

function fail(){
  echo -e "\n------------------------\nFailing '$@'\n------------------------\n" >&2
  echo -e "\n@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
  echo -e "\n[main.sh] finished (NOT OK) at $(date)\n"
  echo -e "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@\n"
  exit 1
}

function execute_command(){
  echo "`date` [execute_command] Executing '$@'"
  eval "$@"
  status=$?
  echo "`date` [execute_command] '$@'\nReturn code: ${status}"
  return ${status}
}


# Load the spec file and validate it against common naming conventions (BMK-135)
# Input $1: path to the HEPWL spec file
# [Eventually this could use readonly bash variables and check if any HEPWL_ variables are already defined?]
function load_and_validate_specfile(){
  if [ "$1" == "" ] || [ "$2" != "" ]; then
    echo "Usage: ${FUNCNAME[0]} <hepwlSpecFile>"
    return 1
  fi
  hepwlSpecFile=$1
  echo "[${FUNCNAME[0]}] HEPWL SPEC FILE: ${hepwlSpecFile}"
  if [ ! -f ${hepwlSpecFile} ]; then
    echo "ERROR! spec file '${hepwlSpecFile}' not found"
    return 1
  fi
  echo "[${FUNCNAME[0]}] validate spec file name"
  spec=$(basename ${hepwlSpecFile})
  spec12="${spec%%.spec}"
  if [ "${spec}" == "${spec12}" ]; then
    echo "ERROR! spec file name does not end in .spec"
    return 1
  fi
  spec1=${spec12%-*}
  spec2=${spec12#*-}
  echo "[${FUNCNAME[0]}] experiment: ${spec1}"
  echo "[${FUNCNAME[0]}] workload: ${spec2}"
  ###echo "[${FUNCNAME[0]}] set | grep ^HEPWL :"; set | grep ^HEPWL_
  echo "[${FUNCNAME[0]}] source ${hepwlSpecFile}"
  source ${hepwlSpecFile}
  ###echo "[${FUNCNAME[0]}] set | grep ^HEPWL :"; set | grep ^HEPWL_
  echo "[${FUNCNAME[0]}] validate HEPWL_ environment variables"
  if [ "${HEPWL_BMKOS}" == "" ]; then HEPWL_BMKOS=slc6; fi
  if [ "${HEPWL_BMKDIR}" != "${spec12}" ]; then
    echo "ERROR! Invalid HEPWL_BMKDIR=${HEPWL_BMKDIR}, expected ${spec12}"
    return 1
  elif [ "${HEPWL_BMKEXE}" != "${spec12}-bmk.sh" ]; then
    echo "ERROR! Invalid HEPWL_BMKEXE=${HEPWL_BMKEXE}, expected ${spec12}-bmk.sh"
    return 1
  elif [ "${HEPWL_DOCKERIMAGENAME}" != "${spec12}-bmk" ]; then
    echo "ERROR! Invalid HEPWL_DOCKERIMAGENAME=${HEPWL_DOCKERIMAGENAME}, expected ${spec12}-bmk"
    return 1
  fi
  echo "[${FUNCNAME[0]}] OK"
  return 0
}


# Validate json file: lint syntax (BMK-137)
# [Eventually: check compliance to expected schema (BMK-134)]
# Input $1: path to the json file
function validate_jsonfile(){
  if [ "$1" == "" ] || [ "$2" != "" ]; then
    echo "Usage: ${FUNCNAME[0]} <jsonFile>"
    return 1
  fi
  jsonFile=$1
  echo "[${FUNCNAME[0]}] JSON FILE: ${jsonFile}"
  if [ ! -f ${jsonFile} ]; then
    echo "ERROR! json file '${jsonFile}' not found"
    return 1
  fi
  echo "[${FUNCNAME[0]}] lint json file syntax using jq"
  if ! jq '.' -c < ${jsonFile}; then
    echo "ERROR! json file '${jsonFile}' lint validation failed"
    return 1
  fi
  return 0
}


# Mount the cvmfs repos specified in $HEPWL_CVMFSREPOS
# Input environment variable ${HEPWL_CVMFSREPOS}: cvmfs repos to mount
# Input environment variable ${MAIN_CVMFSTRACESDIR}: directory containing the cvmfs trace files
function mount_cvmfs(){
  echo "[mount_cvmfs] ................................................"
  echo "[mount_cvmfs] starting at $(date)"
  echo "[mount_cvmfs] current directory is $(pwd)"
  if [ "$HEPWL_CVMFSREPOS" == "" ]; then fail "HEPWL_CVMFSREPOS is not set"; fi
  echo "[mount_cvmfs] mounting cvmfs repositories $HEPWL_CVMFSREPOS"
  echo "NB: it's fine if there is a single error message such as 'Failed to get D-Bus connection: Operation not permitted'"
  if [ ! -e $MAIN_CVMFSTRACESDIR ]; then
    mkdir -p $MAIN_CVMFSTRACESDIR || fail "[mount_cvmfs] cannot create $MAIN_CVMFSTRACESDIR"
    chown cvmfs $MAIN_CVMFSTRACESDIR || fail "[mount_cvmfs] cannot chown $MAIN_CVMFSTRACESDIR"
  fi
  cat > /etc/cvmfs/default.local <<EOF
CVMFS_REPOSITORIES=${HEPWL_CVMFSREPOS}
CVMFS_QUOTA_LIMIT=6000
CVMFS_CACHE_BASE=/scratch/cache/cvmfs2
CVMFS_MOUNT_RW=yes
CVMFS_HTTP_PROXY="http://squid.cern.ch:8060|http://ca-proxy.cern.ch:3128;DIRECT"
CVMFS_TRACEFILE=${MAIN_CVMFSTRACESDIR}/cvmfs-@fqrn@.trace.log
EOF
  mkdir -p  /etc/cvmfs/config.d
  echo "export CMS_LOCAL_SITE=/cvmfs/cms.cern.ch/SITECONF/T0_CH_CERN" > /etc/cvmfs/config.d/cms.cern.ch.local

  # NEW OPTION 1 (BMK-145) - main.sh as a subprocess
  #if [ -e /cvmfs ]; then fail "/cvmfs already exists"; fi # 1-inception
  #ln -sf $CIENV_CVMFSVOLUME /cvmfs # replaces "docker run -v $CIENV_CVMFSVOLUME:/cvmfs:shared"? IT DOES NOT WORK...
  #if [ ! -d /cvmfs ]; then fail "/cvmfs does not exist"; fi # assume that /cvmfs has been created by now

  # OLD OPTION 2 (BMK-145) - main.sh as an entrypoint of docker run
  [ -d /cvmfs ] || fail "[mount_cvmfs] /cvmfs does not exist" # assume that /cvmfs has been created by now (e.g. by docker run -v $CIENV_CVMFSVOLUME:/cvmfs:shared)

  cvmfs_config setup nostart || fail "[mount_cvmfs] problem with cvmfs_config setup nostart" # this would create /cvmfs if it did not exist yet
  for repo in `echo ${HEPWL_CVMFSREPOS}| sed -e 's@,@ @g'`; do
    umount /cvmfs/$repo # OPTION 2 ONLY - NEEDED AT ALL?
    rm -rf /cvmfs/$repo # OPTION 2 ONLY - NEEDED AT ALL?
    mkdir /cvmfs/$repo # Assume that /cvmfs has been created by now
    mount -t cvmfs $repo /cvmfs/$repo
    echo "[mount_cvmfs] ls -l /cvmfs/$repo"
    ls -l /cvmfs/$repo
  done
  echo "[mount_cvmfs] finished at $(date)"
  return 0
}


# Unmount the cvmfs repos specified in $HEPWL_CVMFSREPOS
# Input environment variable ${HEPWL_CVMFSREPOS}: cvmfs repos to unmount
function unmount_cvmfs(){
  echo "[unmount_cvmfs] ................................................"
  echo "[unmount_cvmfs] starting at $(date)"
  echo "[unmount_cvmfs] current directory is $(pwd)"
  if [ "$HEPWL_CVMFSREPOS" == "" ]; then fail "HEPWL_CVMFSREPOS is not set"; fi
  echo "[unmount_cvmfs] unmounting cvmfs repositories $HEPWL_CVMFSREPOS"
  for repo in `echo ${HEPWL_CVMFSREPOS}| sed -e 's@,@ @g'`; do
    umount /cvmfs/$repo || echo "WARNING! Could not umount /cvmfs/$repo"
    rm -rf /cvmfs/$repo || echo "WARNING! Could not remove /cvmfs/$repo"
  done
  echo "[unmount_cvmfs] finished at $(date)"
  return 0
}


# Build a docker image
# [This is called twice: to build the image with cvmfs (cvmfs-shrink) and without cvmfs (standalone image)]
# Input $1: docker image, without registry prefix (image_name:image_tag)
# Input environment variable ${CIENV_HEPWL_SPECFILE}: spec file for the image to be built
# Input environment variable ${MAIN_HEPWLBUILDDIR}: build dir below CIENV_JOBDIR (copy of HEPWL spec dir)
# Output: image stored in the local Docker image registry
function build_docker_image(){
  echo "[build_docker_image] ................................................"
  echo "[build_docker_image] starting at $(date)"
  echo "[build_docker_image] current directory is $(pwd)"
  if [ "$1" == "" ]; then fail "[build_docker_image] No image name provided. Failing "; fi
  theimage=$1
  echo "[build_docker_image] " $theimage
  cd ${MAIN_HEPWLBUILDDIR}
  generate_Dockerfile -s $CIENV_HEPWL_SPECFILE -H ./common/Dockerfile.header -T ./common/Dockerfile.template || fail "[build_docker_image] generate_Dockerfile"
  cat Dockerfile
  echo -e "\n[build_docker_image] docker build of ${theimage} starting at $(date)\n"
  docker build -t "${theimage}" . || fail "[build_docker_image] docker build -t ${theimage} ."
  ###docker build --build-arg CACHEBUST=$(date +%s) -t "${theimage}" . || fail "[build_docker_image] docker build -t ${theimage} ."
  echo "[build_docker_image] finished at $(date)"
  return 0
}


# Build the HEP workload image with cvmfs mounted, then run it and produce a cvmfs trace file
# Input environment variable ${HEPWL_DOCKERIMAGENAME}: image name for the HEP workload
# Input environment variable ${HEPWL_BMKOPTS}: options for the HEP workload script
# Input environment variable ${MAIN_HEPWLBUILDDIR}: build dir below CIENV_JOBDIR (copy of HEPWL spec dir)
# Input environment variable ${CIENV_HEPWL_SPECFILE}: spec file for the image to be built
# Input environment variable ${CIENV_JOBDIR}/results: host directory where results should be stored
# Input environment variable ${CIENV_CVMFSVOLUME}: host directory where cvmfs is mounted?
# Input environment variable ${MAIN_CVMFSTRACESDIR}: directory containing the cvmfs trace files
# Output: status code for the success of the test and results in ${CIENV_JOBDIR}/results
# Output: cvmfs trace stored in ${MAIN_CVMFSTRACESDIR}
function run_docker_wl(){
  echo "[run_docker_wl] ................................................"
  echo "[run_docker_wl] starting at $(date)"
  echo "[run_docker_wl] current directory is $(pwd)"
  if [ -z "$HEPWL_BMKOPTS" ]; then HEPWL_BMKOPTS=""; fi
  echo "[run_docker_wl] HEPWL_BMKOPTS options: $HEPWL_BMKOPTS"
  if [ -e $MAIN_HEPWLBUILDDIR/cvmfs ]; then
    echo "[run_docker_wl] removing cvmfs dir in $MAIN_HEPWLBUILDDIR/"
    rm -rf $MAIN_HEPWLBUILDDIR/cvmfs
  fi
  mkdir $MAIN_HEPWLBUILDDIR/cvmfs
  mkdir $MAIN_HEPWLBUILDDIR/cvmfs/.keepme
  mkdir $MAIN_HEPWLBUILDDIR/cvmfs.provenance
  mkdir $MAIN_HEPWLBUILDDIR/cvmfs.provenance/.keepme
  # [NB ./cvmfs here is empty, it only contains .keepme]
  theimage="$HEPWL_DOCKERIMAGENAME:cvmfs-shrink"
  echo "[run_docker_wl] Building temporary docker image $theimage"
  build_docker_image $theimage
  strace=""
  ###strace="--cap-add SYS_PTRACE" # optionally add SYS_PTRACE capability to use strace (see https://github.com/moby/moby/issues/21051)
  echo -e "\n[run_docker_wl] Run WL in docker (to extract cvmfs) via execute_command - started"

  # NEW OPTION 1 (BMK-145) - main.sh as a subprocess
  #execute_command docker run ${strace} --rm -v $CIENV_JOBDIR/results:/results -v $MAIN_HEPWLBUILDDIR:$MAIN_HEPWLBUILDDIR -w $MAIN_HEPWLBUILDDIR -v /cvmfs:/cvmfs:shared $theimage $HEPWL_BMKOPTS -d || fail "[run_docker_wl] docker run $theimage"

  # OLD OPTION 2 (BMK-145) - main.sh as an entrypoint of docker run
  execute_command docker run ${strace} --rm -v $CIENV_JOBDIR/results:/results -v $MAIN_HEPWLBUILDDIR:$MAIN_HEPWLBUILDDIR -w $MAIN_HEPWLBUILDDIR -v $CIENV_CVMFSVOLUME:/cvmfs:shared $theimage $HEPWL_BMKOPTS -d || fail "[run_docker_wl] docker run $theimage"

  echo -e "[run_docker_wl] Run WL in docker (to extract cvmfs) via execute_command - completed\n"
  for acvmfs in `ls ${MAIN_CVMFSTRACESDIR} | sed -e 's@cvmfs-\([^\.]*\)\.cern\.ch.*@\1@'`; do
    echo "[run_docker_wl] cvmfs flush trace for $acvmfs"
    if ! cvmfs_talk -i ${acvmfs}.cern.ch tracebuffer flush; then  # fix BMK-3 (see CVM-1682)
      fail "[run_docker_wl] cvmfs flush $acvmfs" # fix BMK-136 (flush was silently failing, leading to missing cvmfs files)
    fi
  done
  echo "[run_docker_wl] validate json file" # see BMK-137
  jsonFile=$(ls -1tr $CIENV_JOBDIR/results/*/${HEPWL_BMKDIR}_summary.json 1> >( head -1 ) ) || fail "[run_docker_wl] json summary file not found" # process substitution retains error code
  validate_jsonfile $jsonFile || fail "[run_docker_wl] validate json file"
  echo "[run_docker_wl] finished at $(date)"
  return 0
}


# Create a spec from the cvmfs trace file, then run shrinkwrap to create a cvmfs export
# Input environment variable ${MAIN_HEPWLBUILDDIR}: build dir below CIENV_JOBDIR (copy of HEPWL spec dir)
# Input environment variable ${HEPWL_EXTEND_<repo>_SPEC}: optional extra cvmfs spec file
# Input environment variable ${CIENV_JOBDIR}: host directory where the cvmfs config should be stored
# Input environment variable ${CIENV_JOBDIR}/results: host directory where results should be stored
# Input environment variable ${MAIN_CVMFSTRACESDIR}: directory containing the cvmfs trace files
# Input environment variable ${MAIN_CVMFSEXPORTDIR}: directory where the cvmfs export should be stored
# Output: cvmfs export in ${MAIN_CVMFSEXPORTDIR}/cvmfs
function run_shrinkwrap(){
  echo "[run_shrinkwrap] ................................................"
  echo "[run_shrinkwrap] starting at $(date)"
  echo "[run_shrinkwrap] current directory is $(pwd)"
  echo "MAIN_CVMFSEXPORTDIR $MAIN_CVMFSEXPORTDIR"
  if [ -e  ${MAIN_CVMFSEXPORTDIR} ]; then
    echo "[run_shrinkwrap] ${MAIN_CVMFSEXPORTDIR} already exists: will remove it"
    ###echo "[run_shrinkwrap] ${MAIN_CVMFSEXPORTDIR} already exists: remove it? (y/[n]) "
    ###read myansw
    ###if [ "$myansw" == "n" ]; then return 1; fi
    rm -rf ${MAIN_CVMFSEXPORTDIR}
  fi
  mkdir -p ${MAIN_CVMFSEXPORTDIR}/cvmfs
  cvmfs_shrink_conf=$CIENV_JOBDIR/generic_config.cern.ch.config # no need to export this
  cat > ${cvmfs_shrink_conf} <<EOF
CVMFS_CACHE_BASE=/var/lib/cvmfs/shrinkwrap
CVMFS_HTTP_PROXY=DIRECT
CVMFS_KEYS_DIR=/etc/cvmfs/keys/cern.ch # from /etc/cvmfs/domain.d/cern.ch.conf
CVMFS_MOUNT_DIR=/cvmfs # from /etc/cvmfs/default.conf
CVMFS_SERVER_URL='http://cvmfs-stratum-zero-hpc.cern.ch/cvmfs/@fqrn@' # from /etc/cvmfs/domain.d/cern.ch.conf
CVMFS_SHARED_CACHE=no
export CMS_LOCAL_SITE=T0_CH_CERN
EOF
  for acvmfs in `ls ${MAIN_CVMFSTRACESDIR} | grep "\.log"`; do
    echo "[run_shrinkwrap] ... shrinking  " $acvmfs;
    specname=`echo $acvmfs | sed -e 's@trace\.log@spec\.txt@'`
    reponame=`echo $acvmfs | sed -e 's@cvmfs-\([^\.]*\)\.cern\.ch.*@\1\.cern.ch@'`
    echo "[run_shrinkwrap] specname $specname"
    echo "[run_shrinkwrap] reponame $reponame"
    date
    echo "[run_shrinkwrap] python /usr/libexec/cvmfs/shrinkwrap/spec_builder.py --policy=exact ${MAIN_CVMFSTRACESDIR}/$acvmfs ${MAIN_CVMFSTRACESDIR}/$specname"
    if ! python /usr/libexec/cvmfs/shrinkwrap/spec_builder.py --policy=exact ${MAIN_CVMFSTRACESDIR}/$acvmfs ${MAIN_CVMFSTRACESDIR}/$specname; then
      fail "[run_shrinkwrap] spec_builder.py" # fix BMK-136 (spec_builder was silently failing, leading to missing cvmfs files)
    fi
    echo "[run_shrinkwrap] saving $specname on ${CIENV_JOBDIR}/results/$specname"
    cp ${MAIN_CVMFSTRACESDIR}/$specname ${CIENV_JOBDIR}/results/
    date
    trimname=${reponame/.cern.ch}
    spec_var=HEPWL_EXTEND_${trimname^^}_SPEC
    if [ ! -z ${!spec_var} ] && [ -e $MAIN_HEPWLBUILDDIR/${!spec_var} ]; then
      echo "[run_shrinkwrap] appending custom paths to ${MAIN_CVMFSTRACESDIR}/$specname based on $MAIN_HEPWLBUILDDIR/${!spec_var}"
      echo " " >> ${MAIN_CVMFSTRACESDIR}/$specname
      cat $MAIN_HEPWLBUILDDIR/${!spec_var} >> ${MAIN_CVMFSTRACESDIR}/$specname
    fi
    echo "[run_shrinkwrap] cvmfs_shrinkwrap --repo $reponame --src-config ${cvmfs_shrink_conf} --spec-file ${MAIN_CVMFSTRACESDIR}/$specname --dest-base ${MAIN_CVMFSEXPORTDIR}/cvmfs/ -j 4"
    cvmfs_shrinkwrap --repo $reponame --src-config ${cvmfs_shrink_conf} --spec-file  ${MAIN_CVMFSTRACESDIR}/$specname --dest-base ${MAIN_CVMFSEXPORTDIR}/cvmfs/ -j 4 || fail "[run_shrinkwrap] cvmfs_shrinkwrap failed"
    date
  done
  echo "[run_shrinkwrap] finished at $(date)"
  return 0
}


# Move the cvmfs export from ${MAIN_CVMFSEXPORTDIR}/cvmfs to ${MAIN_HEPWLBUILDDIR}/cvmfs
# Input environment variable ${MAIN_CVMFSEXPORTDIR}: directory where the cvmfs export has been stored
# Input environment variable ${MAIN_HEPWLBUILDDIR}: build dir below CIENV_JOBDIR (copy of HEPWL spec dir)
# Input environment variable ${MAIN_CVMFSTRACESDIR}: directory containing the cvmfs trace files
# Input environment variable ${HEPWL_DOCKERIMAGETAG}: image tag for the standalone HEP workload
# Output: cvmfs export in ${MAIN_HEPWLBUILDDIR}/cvmfs, to be copied into the docker image
function copy_cvmfs(){
  echo "[copy_cvmfs] ................................................"
  echo "[copy_cvmfs] starting at $(date)"
  echo "[copy_cvmfs] current directory is $(pwd)"
  echo "[copy_cvmfs] remove ${MAIN_CVMFSEXPORTDIR}/cvmfs/.data" # this is a _very_ large (and useless?) directory produced by cvmfs_shrinkwrap
  ###rm -rf ${MAIN_CVMFSEXPORTDIR}/cvmfs/.data # this is slow, rsync is faster (https://unix.stackexchange.com/a/79656)
  cd ${MAIN_CVMFSEXPORTDIR}/cvmfs; mkdir EMPTYDIR; rsync -a --delete EMPTYDIR/ .data || fail "[copy_cvmfs] rsync"; cd - # NB for rsync, add a trailing "/" to the source and none to the target
  date
  if [ -e $MAIN_HEPWLBUILDDIR/cvmfs ]; then
    echo "[copy_cvmfs] removing cvmfs dir in $MAIN_HEPWLBUILDDIR/"
    rm -rf $MAIN_HEPWLBUILDDIR/cvmfs
  fi
  echo "[copy_cvmfs] mv ${MAIN_CVMFSEXPORTDIR}/cvmfs $MAIN_HEPWLBUILDDIR "
  mv ${MAIN_CVMFSEXPORTDIR}/cvmfs $MAIN_HEPWLBUILDDIR || fail "[copy_cvmfs] cannot mv ${MAIN_CVMFSEXPORTDIR}/cvmfs $MAIN_HEPWLBUILDDIR"
  # FIXME: if cms repo, need to copy by hand the SITECONF/local, because it's a sym link
  #if [ -e /cvmfs/cms.cern.ch/SITECONF/local ]; then
  #  cp -r -H /cvmfs/cms.cern.ch/SITECONF/local $MAIN_HEPWLBUILDDIR/cvmfs/cms.cern.ch/SITECONF/ || fail "[copy_cvmfs] cannot cp /cvmfs/cms.cern.ch/SITECONF/local" # BMK-15: do NOT use '.. && ( .. || fail )'
  #fi
  # FIXME: try to run CMS bmks without SITECONF/local (BMK-15)
  if [ -e $MAIN_HEPWLBUILDDIR/cvmfs/cms.cern.ch/SITECONF/local ]; then
    rm -rf $MAIN_HEPWLBUILDDIR/cvmfs/cms.cern.ch/SITECONF/local
  fi
  mkdir -p $MAIN_HEPWLBUILDDIR/cvmfs/cms.cern.ch/SITECONF/local/JobConfig # empty
  echo "[copy_cvmfs] /cvmfs contents copied to $MAIN_HEPWLBUILDDIR/cvmfs"
  ls -l $MAIN_HEPWLBUILDDIR/cvmfs
  if [[ ${HEPWL_DOCKERIMAGETAG} =~ ^v[0-9]*\.[0-9]*$ ]]; then # keep provenance info only in v[0-9]*\.[0-9]* production images (BMK-159)
    echo "[copy_cvmfs] move $MAIN_HEPWLBUILDDIR/cvmfs/.provenance to $MAIN_HEPWLBUILDDIR/cvmfs.provenance"
    mv $MAIN_HEPWLBUILDDIR/cvmfs/.provenance $MAIN_HEPWLBUILDDIR/cvmfs.provenance # move away CI-JOB-xxx-specific files for better caching (BMK-159)
  else
    echo "[copy_cvmfs] remove $MAIN_HEPWLBUILDDIR/cvmfs/.provenance"
    rm -rf $MAIN_HEPWLBUILDDIR/cvmfs/.provenance # completely remove CI-JOB-xxx-specific files for better caching in singularity (BMK-159)
  fi
  echo "[copy_cvmfs] finished at $(date)"
  return 0
}


# Remove the cvmfs copy from ${MAIN_HEPWLBUILDDIR}/cvmfs
function clean_cvmfs_copy(){
  echo "[clean_cvmfs_copy] ................................................"
  echo "[clean_cvmfs_copy] starting at $(date)"
  echo "[clean_cvmfs_copy] current directory is $(pwd)"
  echo "remove cvmfs copy $MAIN_HEPWLBUILDDIR/cvmfs"
  rm -rf "$MAIN_HEPWLBUILDDIR/cvmfs" || fail "[clean_cvmfs_copy] could not remove $MAIN_HEPWLBUILDDIR/cvmfs"
  echo "[clean_cvmfs_copy] finished at $(date)"
  return 0
}


# Build, test and publish the standalone HEP workload image with a local /cvmfs
# Input environment variable ${HEPWL_DOCKERIMAGENAME}: image name for the HEP workload
# Input environment variable ${HEPWL_DOCKERIMAGETAG}: image tag for the standalone HEP workload
# Input environment variable ${CIENV_DOCKERREGISTRY}: registry where the image should be pushed
# Input environment variable ${HEPWL_BMKOPTS}: options for the HEP workload script
# Input environment variable ${CIENV_JOBDIR}/results: host directory where results should be stored
# Output: standalone WL image stored in the local Docker image registry
# Output: status code for the success of the test and results in ${CIENV_JOBDIR}/results
# Output: standalone WL image stored in the remote Docker image registry
function build_standalone_image(){
  echo "[build_standalone_image] ................................................"
  echo "[build_standalone_image] starting at $(date)"
  echo "[build_standalone_image] current directory is $(pwd)"
  theimage="${HEPWL_DOCKERIMAGENAME}":"${HEPWL_DOCKERIMAGETAG}"
  if [ "${CIENV_DOCKERREGISTRY}" != "" ]; then theimage="${CIENV_DOCKERREGISTRY}/${theimage}"; fi
  echo "[build_standalone_image] theimage: $theimage"
  # [NB ./cvmfs here contains the data copied by the function copy_cvmfs]
  build_docker_image "$theimage" || fail "[build_standalone_image] build_docker_image $theimage"
  echo "[build_standalone_image] finished at $(date)"
  return 0
}


# Test standalone image in singularity
# Input environment variable ${HEPWL_DOCKERIMAGENAME}: image name for the HEP workload
# Input environment variable ${HEPWL_DOCKERIMAGETAG}: image tag for the standalone HEP workload
# Input environment variable ${CIENV_DOCKERREGISTRY}: registry where the image should be pushed
# Input environment variable ${HEPWL_BMKOS}: O/S for the HEP workload script
# Input environment variable ${HEPWL_BMKOPTS}: options for the HEP workload script
# Input environment variable ${CIENV_JOBDIR}/results: host directory where results should be stored
# Input environment variable ${CIENV_SINGULARITYCACHE}: singularity cache directory
# Output: status code for the success of the test and results in ${CIENV_JOBDIR}/results
function test_standalone_image_singularity(){
  echo "[test_standalone_image_singularity] ................................................"
  echo "[test_standalone_image_singularity] starting at $(date)"
  echo "[test_standalone_image_singularity] current directory is $(pwd)"
  if [ "$CI_JOB_NAME" == "" ] || [ "$CI_JOB_NAME" == "noCI" ]; then
    echo "[test_standalone_image_singularity] skipping singularity test CI_JOB_NAME='$CI_JOB_NAME'"
  elif [[ ${HEPWL_DOCKERIMAGETAG} =~ ^*NS$ ]]; then # for internal tests: skip singularity if tag ends by NS (No Singularity)
    echo "[test_standalone_image_singularity] skipping singularity test HEPWL_DOCKERIMAGETAG='${HEPWL_DOCKERIMAGETAG}'"
  else
    echo "[test_standalone_image_singularity] executing singularity test for HEPWL_BMKOS='${HEPWL_BMKOS}'"
    export SINGULARITY_CACHEDIR=$CIENV_SINGULARITYCACHE # use a common singularity cache to speed up singularity runs (BMK-159)
    singularityregistry="${CIENV_DOCKERREGISTRY}"
    theimage="${HEPWL_DOCKERIMAGENAME}":"${HEPWL_DOCKERIMAGETAG}"
    echo $CI_BUILD_TOKEN | docker login -u gitlab-ci-token --password-stdin gitlab-registry.cern.ch || fail "[test_standalone_image_singularity] docker login"
    execute_command docker tag ${singularityregistry}/${theimage} ${singularityregistry}/${HEPWL_DOCKERIMAGENAME}:test_ci_singularity || fail "[test_standalone_image_singularity] docker tag"
    execute_command docker push ${singularityregistry}/${HEPWL_DOCKERIMAGENAME}:test_ci_singularity
    status=$?
    if [ $status -eq 0 ]; then
      echo -e "\n[test_standalone_image_singularity] Run WL in singularity (to test the image) via execute_command - started" &&
      execute_command singularity run -B ${CIENV_JOBDIR}/results:/results docker://${singularityregistry}/${HEPWL_DOCKERIMAGENAME}:test_ci_singularity $HEPWL_BMKOPTS -d
      status=$?
      echo -e "\n[test_standalone_image_singularity] Run WL in singularity (to test the image) via execute_command - completed (status=$status)"
    fi
    docker rmi -f ${singularityregistry}/${HEPWL_DOCKERIMAGENAME}:test_ci_singularity # remove the local singularity test image
    echo "[test_standalone_image_singularity] clean the singularity cache" # BMK-160
    ls -ltr $SINGULARITY_CACHEDIR/oci-tmp/*/${HEPWL_DOCKERIMAGENAME}_test_ci_singularity.sif
    sifs=$(ls -tr1 $SINGULARITY_CACHEDIR/oci-tmp/*/${HEPWL_DOCKERIMAGENAME}_test_ci_singularity.sif | head -n-1)
    if [ "$sifs" == "" ]; then
      echo "[test_standalone_image_singularity] no sif files to remove"
    else
      for sif in $sifs; do
        echo "[test_standalone_image_singularity] remove $(dirname $sif)"
        rm -rf $(dirname $sif)
      done
    fi
    if [ $status -ne 0 ]; then fail "[test_standalone_image_singularity] Run WL in singularity"; fi
    echo "[test_standalone_image_singularity] validate json file" # see BMK-137
    jsonFile=$(ls -1tr $CIENV_JOBDIR/results/*/${HEPWL_BMKDIR}_summary.json 1> >( head -1 ) ) || fail "[test_standalone_image_singularity] json summary file not found" # process substitution retains error code
    validate_jsonfile $jsonFile || fail "[test_standalone_image_singularity] validate json file"
  fi
  echo "[test_standalone_image_singularity] finished at $(date)"
  return 0
}


# Test the standalone HEP workload image (in the local registry) with a local /cvmfs and test it
# Input environment variable ${HEPWL_DOCKERIMAGENAME}: image name for the HEP workload
# Input environment variable ${HEPWL_DOCKERIMAGETAG}: image tag for the standalone HEP workload
# Input environment variable ${CIENV_DOCKERREGISTRY}: registry where the image should be pushed
# Input environment variable ${HEPWL_BMKOPTS}: options for the HEP workload script
# Input environment variable ${CIENV_JOBDIR}/results: host directory where results should be stored
# Output: status code for the success of the test and results in ${CIENV_JOBDIR}/results
function test_standalone_image_docker(){
  echo "[test_standalone_image_docker] ................................................"
  echo "[test_standalone_image_docker] starting at $(date)"
  echo "[test_standalone_image_docker] current directory is $(pwd)"
  theimage="${HEPWL_DOCKERIMAGENAME}":"${HEPWL_DOCKERIMAGETAG}"
  if [ "${CIENV_DOCKERREGISTRY}" != "" ]; then theimage="${CIENV_DOCKERREGISTRY}/${theimage}"; fi
  echo "[test_standalone_image_docker] theimage: $theimage"
  if [ -z "$HEPWL_BMKOPTS" ]; then HEPWL_BMKOPTS=""; fi
  strace=""
  #net_conn="--network none" # by default run the test without network connectivity
  net_conn="" # by default run the test without network connectivity
  if [ "$MAIN_NETWORKCONN" == "1" ]; then net_conn=""; fi
  ###strace="--cap-add SYS_PTRACE" # optionally add SYS_PTRACE capability to use strace (see https://github.com/moby/moby/issues/21051)
  echo -e "\n[test_standalone_image_docker] Run WL in docker (to test the image) via execute_command - started"
  if ! execute_command docker run ${strace} ${net_conn} --rm -v $CIENV_JOBDIR/results:/results $theimage $HEPWL_BMKOPTS -d; then
    docker rmi -f $theimage # BMK-122
    fail "[test_standalone_image_docker] docker run $theimage"
  fi
  echo -e "[test_standalone_image_docker] Run WL in docker (to test the image) via execute_command - completed\n"
  echo "[test_standalone_image_docker] validate json file" # see BMK-137
  jsonFile=$(ls -1tr $CIENV_JOBDIR/results/*/${HEPWL_BMKDIR}_summary.json 1> >( head -1 ) ) || fail "[test_standalone_image_docker] json summary file not found" # process substitution retains error code
  validate_jsonfile $jsonFile || fail "[test_standalone_image_docker] validate json file"
  echo "[test_standalone_image_docker] finished at $(date)"
  return 0
}


# Publish the standalone HEP workload image with a local /cvmfs
# Input environment variable ${HEPWL_DOCKERIMAGENAME}: image name for the HEP workload
# Input environment variable ${HEPWL_DOCKERIMAGETAG}: image tag for the standalone HEP workload
# Input environment variable ${CIENV_DOCKERREGISTRY}: registry where the image should be pushed
# Input environment variable ${CI_BUILD_TOKEN}: authentication token for the gitlab registry
# Output: standalone WL image stored in the remote Docker image registry
function publish_standalone_image(){
  echo "[publish_standalone_image] ................................................"
  echo "[publish_standalone_image] starting at $(date)"
  echo "[publish_standalone_image] current directory is $(pwd)"
  if [ "${CIENV_DOCKERREGISTRY}" == "" ]; then
    echo "[publish_standalone_image] WARNING: empty CIENV_DOCKERREGISTRY, nothing to do"
  else
    theimage="${CIENV_DOCKERREGISTRY}/${HEPWL_DOCKERIMAGENAME}:${HEPWL_DOCKERIMAGETAG}"
    echo "[publish_standalone_image] theimage: $theimage"
    echo $CI_BUILD_TOKEN | docker login -u gitlab-ci-token --password-stdin gitlab-registry.cern.ch || fail "[publish_standalone_image] docker login"
    echo "[publish_standalone_image] docker push ${theimage}"
    docker push "${theimage}" || fail "[publish_standalone_image] docker push ${theimage}"
    if [[ ${HEPWL_DOCKERIMAGETAG} =~ ^v[0-9]*\.[0-9]*$ ]]; then # flag as latest only images that respect the format v[0-9]*\.[0-9]*
      theimage_latest=${CIENV_DOCKERREGISTRY}/${HEPWL_DOCKERIMAGENAME}:latest
      docker tag "${theimage}" "${theimage_latest}" || fail "[publish_standalone_image] docker tag ${theimage} ${theimage_latest}"
      docker push "${theimage_latest}" || fail "[publish_standalone_image] docker push ${theimage_latest}"
      docker rmi "${theimage_latest}" # BMK-122 clean local tag latest to free up space
 
      # Tag the image also with the git commit sha id (BMK-319) 
      theimage_shacommit=${CIENV_DOCKERREGISTRY}/${HEPWL_DOCKERIMAGENAME}:${CI_COMMIT_SHORT_SHA} 
      docker tag "${theimage}" "${theimage_shacommit}" || fail "[publish_standalone_image] docker tag ${theimage} ${theimage_shacommit}"
      docker push "${theimage_shacommit}" || fail "[publish_standalone_image] docker push ${theimage_shacommit}"
      docker rmi "${theimage_shacommit}" # BMK-122 clean local tag latest to free up space
    fi
    theimage_cilatest=${HEPWL_DOCKERIMAGENAME}:cilatest # create a local tag cilatest to allow caching (BMK-159)
    docker rmi "${theimage_cilatest}" || echo "No cached image ${theimage_cilatest} to be removed"  # Clean previous cache image (BMK-320)
    docker tag "${theimage}" "${theimage_cilatest}" || fail "[publish_standalone_image] docker tag ${theimage} ${theimage_cilatest}"
    echo "[publish_standalone_image] remove local image ${theimage}"
    docker rmi ${theimage} # BMK-122 clean local image to free up space (keep only cilatest tag to allow caching BMK-159)
  fi
  echo "[publish_standalone_image] finished at $(date)"
  return 0
}


# Announce the standalone HEP workload image with a local /cvmfs (BMK-80)
# (send an email from ${CI_MAIL_FROM} to ${CI_ANNOUNCE_TO} announcing a new image created in ${CI_JOB_URL})
# Input environment variable ${HEPWL_DOCKERIMAGENAME}: image name for the HEP workload
# Input environment variable ${HEPWL_DOCKERIMAGETAG}: image tag for the standalone HEP workload
# Input environment variable ${CIENV_DOCKERREGISTRY}: registry where the image should be pushed
# Input environment variable ${CI_BUILD_TOKEN}: authentication token for the gitlab registry
# Input environment variables ${CI_MAIL_FROM}, ${CI_ANNOUNCE_TO} and ${CI_JOB_URL}
# Input environment variable ${HEPWL_BMKANNOUNCE}: if exists and "false", do not announce the release
function announce_standalone_image(){
  echo "[announce_standalone_image] ................................................"
  echo "[announce_standalone_image] starting at $(date)"
  echo "[announce_standalone_image] current directory is $(pwd)"
  echo "[announce_standalone_image] send mail from CI_MAIL_FROM='${CI_MAIL_FROM}'"
  echo "[announce_standalone_image] send mail to CI_ANNOUNCE_TO='${CI_ANNOUNCE_TO}'"
  if [ "${CIENV_DOCKERREGISTRY}" == "" ]; then
    echo "[annnounce_standalone_image] WARNING: empty CIENV_DOCKERREGISTRY, nothing to do"
  else
    theimage="${CIENV_DOCKERREGISTRY}/${HEPWL_DOCKERIMAGENAME}:${HEPWL_DOCKERIMAGETAG}"
    echo "[announce_standalone_image] theimage: $theimage"
    if [ "${HEPWL_BMKANNOUNCE}" == "false" ]; then
      echo "[announce_standalone_image] WARNING! no mail sent, HEPWL_BMKANNOUNCE is '${HEPWL_BMKANNOUNCE}'"
    elif ! [[ ${HEPWL_DOCKERIMAGETAG} =~ ^v[0-9]*\.[0-9]*$ ]]; then # announce only images that respect the format v[0-9]*\.[0-9]* (BMK-147)
      echo "[announce_standalone_image] WARNING! no mail sent, tag ${HEPWL_DOCKERIMAGETAG} is not a vXX.YY release tag"
    elif [ "${CI_MAIL_FROM}" == "" ] || [ "${CI_ANNOUNCE_TO}" == "" ]; then # NB these variables are set only in the upstream repo, not in forks
      echo "[announce_standalone_image] WARNING! no mail sent, invalid CI_MAIL_FROM or CI_ANNOUNCE_TO"
    else
      postfix start
      announcement="announce.txt"
      echo -e "Dear HEP Benchmark developers, \n" > $announcement
      echo -e "we are pleased to inform that a new version has been released for the container image \n\n${theimage}" >> $announcement
      echo -e "COMMIT DESCRIPTION $CI_COMMIT_DESCRIPTION" >> $announcement
      echo -e "\nPlease DO NOT REPLY\nReport automatically generated from GitLab CI in job ${CI_JOB_URL}\n[$(date)]" >> $announcement
      echo -e "\nYours sincerely,\nHEPiX Benchmarking Working Group\n\n" >> $announcement
      cat $announcement
      cat $announcement | mail -r ${CI_MAIL_FROM} -s "New Docker container available $theimage" ${CI_ANNOUNCE_TO}
      sleep 100s # keep the container alive, otherwise no email is sent (emails are sent only once per minute, see BMK-80)
    fi
  fi
  echo "[announce_standalone_image] finished at $(date)"
  return 0
}


# Before building a new image $HEPWL_DOCKERIMAGENAME:$HEPWL_DOCKERIMAGETAG, check that the required
# tag HEPWL_DOCKERIMAGETAG is greater than the "latest" tag in the registry, otherwise fail
# Input environment variable ${HEPWL_DOCKERIMAGENAME}: image name for the HEP workload
# Input environment variable ${HEPWL_DOCKERIMAGETAG}: image tag for the standalone HEP workload
# Input environment variable ${CIENV_DOCKERREGISTRY}: registry where the image should be pushed
function check_tag_version(){
  echo "[check_tag_version] ................................................"
  echo "[check_tag_version] starting at $(date)"
  echo "[check_tag_version] current directory is $(pwd)"
  theimage=${CIENV_DOCKERREGISTRY}/${HEPWL_DOCKERIMAGENAME}
  if [[ ! ${HEPWL_DOCKERIMAGETAG} =~ ^v[0-9]*\.[0-9]*$ ]]; then
    echo "[check_tag_version] image tag ${HEPWL_DOCKERIMAGETAG} does NOT respect the format v[0-9]*\.[0-9]* "
    return 0
  fi
  echo "[check_tag_version] testing image ${theimage}:latest"
  res=`skopeo inspect docker://${theimage}:latest`
  echo ${res}
  oldsha=`echo ${res} | jq '.["Digest"]' | sed -e 's@"@@g'`
  tags=`echo ${res} | jq '.["RepoTags"][] | select (.!="latest")' | sed -e 's@"@@g'`
  echo "[check_tag_version] signature ${oldsha}"
  echo "[check_tag_version] tags ${tags} " | xargs
  oldtag=''
  for tag in ${tags}
  do
    testsha=`skopeo inspect docker://${theimage}:${tag} | jq '.["Digest"]' | sed -e 's@"@@g'`
    if [ "${testsha}" == "${oldsha}" ] && [[ ${tag} =~ ^v[0-9]*\.[0-9]*$ ]]; then
      oldtag=${tag}
      echo "[check_tag_version] tag 'latest' is currently associated to ${oldtag}"
      break;
    fi
  done
  if [ "${oldtag}" == "" ]; then
    echo "[check_tag_version] tag 'latest' is currently not associated to any tag"
  else
    oldtag=${oldtag/v/}
    newtag=${HEPWL_DOCKERIMAGETAG/v/}
    oldtagmajor=${oldtag%%.*}
    oldtagminor=${oldtag##*.}
    newtagmajor=${newtag%%.*}
    newtagminor=${newtag##*.}
    if [ $newtagmajor -lt $oldtagmajor ]; then
      echo -e "\n[check_tag_version] new image tag ${newtag} MUST be greater than tag ${oldtag} currently associated to ${theimage}:latest\n\n"
      return 1
    elif [ $newtagmajor -eq $oldtagmajor ] && [ $newtagminor -le $oldtagminor ]; then
      echo -e "\n[check_tag_version] new image tag ${newtag} MUST be greater than tag ${oldtag} currently associated to ${theimage}:latest\n\n"
      return 1
    fi
  fi
  echo "[check_tag_version] finished at $(date)"
  return 0
}


function execute_procedure(){
  echo "[execute_procedure] ................................................"
  echo "[execute_procedure] starting at $(date)"
  echo "[execute_procedure] current directory is $(pwd)"
  echo "[execute_procedure] option '$1'"
  case $1 in
    none)
      echo "Do not run any step of the procedure."
      ;;
    sleep)
      echo -e "\nSleep and stay alive just to expose cvmfs"
      echo "cvmfs mount point $CIENV_CVMFSVOLUME"
      echo "You can mount the available cvmfs as follow:"
      echo "docker run -v $CIENV_CVMFSVOLUME:/cvmfs:shared ..."
      sleep infinity
      ;;
    all)
      echo "Run the full sequence."
      check_tag_version || fail "[execute_procedure] $1: check_tag_version"
      run_docker_wl || fail "[execute_procedure] $1: run_docker_wl"
      run_shrinkwrap || fail "[execute_procedure] $1: run_shrinkwrap"
      copy_cvmfs || fail "[execute_procedure] $1: copy_cvmfs"
      build_standalone_image || fail "[execute_procedure] $1: build_standalone_image"
      clean_cvmfs_copy || fail "[execute_procedure] $1: clean_cvmfs_copy"
      test_standalone_image_docker || fail "[execute_procedure] $1: test_standalone_image_docker"
      test_standalone_image_singularity || fail "[execute_procedure] $1: test_standalone_image_singularity"
      publish_standalone_image || fail "[execute_procedure] $1: publish_standalone_image"
      announce_standalone_image || fail "[execute_procedure] $1: announce_standalone_image"
      ;;
    *)
      fail "[execute_procedure] Unknown option $1"
  esac
  echo "[execute_procedure] finished at $(date)"
  return 0
}

### Main

echo -e "\n@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
echo -e "\n[main.sh] starting at $(date)\n"
echo -e "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@\n"

echo -e "Current directory is $(pwd)\n"

echo "CIENV_JOBDIR is ${CIENV_JOBDIR}" # within docker this may come from .env.file

echo "CI_PROJECT_DIR is ${CI_PROJECT_DIR}" # within docker this may come from .env.file

scriptDir=`dirname $0`
echo "scriptDir is ${scriptDir}"

# Load function generate_Dockerfile()
. ${scriptDir}/generate_Dockerfile.sh || fail '[main.sh] . generate_Dockerfile.sh'

# These are fixed params, to be moved in an etc file
export MAIN_CVMFSTRACESDIR=$CIENV_JOBDIR/cvmfs-traces/
export MAIN_CVMFSEXPORTDIR=$CIENV_JOBDIR/cvmfs-export/

# [NB MAIN_NETWORKCONN, which was only used in main.sh, is now a local variable]
MAIN_NETWORKCONN=0 # this can be overridden via the -n command line option

# NEW OPTION 1 (BMK-145) - main.sh as a subprocess
# Previously these environment variables were reset to default values here
# To make this cleaner (BMK-145), it is now expected that they must have been set in advance
#for var in CIENV_HEPWL_SPECFILE CIENV_BUILDEVENT CIENV_DOCKERREGISTRY CIENV_MOUNTCVMFS CIENV_JOBDIR MAIN_NETWORKCONN; do
#  # Bash indirection ${!var}: see http://mywiki.wooledge.org/BashFAQ/006#Indirection
#  if [ "${!var}" == "" ]; then echo "ERROR! $var is not set"; exit 1; fi
#  echo "$var=${!var}"
#done

# Parameters to be passed by command line
# 1: SPEC file path
# 2: optional export CIENV_DOCKERREGISTRY gitlab-registry.cern.ch/giordano/hep-workloads
while getopts "hds:r:e:m" o; do
  case ${o} in
    s)
      if [ "$OPTARG" != "" ]; then export CIENV_HEPWL_SPECFILE="$OPTARG"; fi
      ;;
    e)
      if [ "$OPTARG" != "" ]; then export CIENV_BUILDEVENT="$OPTARG"; fi
      ;;
    r)
      if [ "$OPTARG" != "" ]; then export CIENV_DOCKERREGISTRY="$OPTARG"; fi
      ;;
    m)
      CIENV_MOUNTCVMFS=1
      ;;
    n)
      MAIN_NETWORKCONN=1
      ;;
    d)
      set -x # Enable debug printouts
      ;;
    h)
      echo "Usage: $0 -s <full path to HEP Workload Spec file> [-e <execution step (none|sleep|all): default is all>] [-r <docker registry>] [-d (enable debug printouts)] [-n (force external network connectivity: default is false)"
      fail "Invalid command line options"
      ;;
  esac
done

# OLD OPTION 2 (BMK-145) - main.sh as an entrypoint of docker run
for var in CIENV_HEPWL_SPECFILE CIENV_BUILDEVENT CIENV_MOUNTCVMFS CIENV_JOBDIR MAIN_NETWORKCONN; do
  # Bash indirection ${!var}: see http://mywiki.wooledge.org/BashFAQ/006#Indirection
  if [ "${!var}" == "" ]; then echo "ERROR! $var is not set"; exit 1; fi
  echo "$var=${!var}"
done
# [NB CIENV_DOCKERREGISTRY can be empty in interactive builds from run_build.sh]
echo "CIENV_DOCKERREGISTRY=$CIENV_DOCKERREGISTRY"

echo -e "\n[main] Input parameters\n-------------"
echo CIENV_HEPWL_SPECFILE $CIENV_HEPWL_SPECFILE
echo CIENV_BUILDEVENT $CIENV_BUILDEVENT
echo CIENV_DOCKERREGISTRY $CIENV_DOCKERREGISTRY
echo CIENV_MOUNTCVMFS $CIENV_MOUNTCVMFS
echo CIENV_JOBDIR "$CIENV_JOBDIR"
echo CIENV_CVMFSVOLUME "$CIENV_CVMFSVOLUME"
echo "-------------"

env | grep "CI_" | sort

if [ "$CIENV_BUILDEVENT" != "none" ] && [ "$CIENV_BUILDEVENT" != "sleep" ] && [ "$CIENV_BUILDEVENT" != "all" ]; then fail "Unknown option CIENV_BUILDEVENT=$CIENV_BUILDEVENT"; fi

if [ "$CIENV_HEPWL_SPECFILE" == "" ]; then fail "SPEC file not specified"; fi

if [ ! -f $CIENV_HEPWL_SPECFILE ]; then fail "SPEC file $CIENV_HEPWL_SPECFILE not found"; fi

cp -dpr $(dirname "$CIENV_HEPWL_SPECFILE") $CIENV_JOBDIR/build-wl
cp -dpr $(dirname "$CIENV_HEPWL_SPECFILE")/../../common $CIENV_JOBDIR/build-wl/common
export MAIN_HEPWLBUILDDIR=$CIENV_JOBDIR/build-wl

CIENV_HEPWL_SPECFILE=$CIENV_JOBDIR/build-wl/${CIENV_HEPWL_SPECFILE##*/}

echo "----------- $CIENV_HEPWL_SPECFILE"
cat "$CIENV_HEPWL_SPECFILE"
echo "-----------"

# This sets all environment variables starting with HEPWL_ used in this script (BMK-118)
# It should always set HEPWL_BMKEXE, HEPWL_BMKOPTS, HEPWL_BMKDIR, HEPWL_BMKDESCRIPTION,
# as well as HEPWL_DOCKERIMAGENAME, HEPWL_DOCKERIMAGETAG and HEPWL_CVMFSREPOS
# It may optionally set also HEPWL_BMKOS, HEPWL_BMKANNOUNCE and HEPWL_EXTEND_<repo>_SPEC
if ! load_and_validate_specfile "$CIENV_HEPWL_SPECFILE"; then fail "invalid SPEC file"; fi

if [[ "$CIENV_MOUNTCVMFS" -gt 0 ]]; then
  mount_cvmfs || fail '[main.sh] mount_cvmfs'
else
  echo -e "\n[main.sh] WARNING: cvmfs will not be mounted\n"
fi

execute_procedure "$CIENV_BUILDEVENT"

if [[ "$CIENV_MOUNTCVMFS" -gt 0 ]]; then
  unmount_cvmfs || fail '[main.sh] unmount_cvmfs'
else
  echo -e "\n[main.sh] WARNING: cvmfs will not be unmounted\n"
fi

echo -e "\n@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
echo -e "\n[main.sh] finished (OK) at $(date)\n"
echo -e "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@\n"
